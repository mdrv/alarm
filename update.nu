#!/usr/bin/env nu

# AUR package update script - Nushell version
# Updates packages defined in update.jsonc

const USER = {
	NAME: "Umar Alfarouk"
	EMAIL: "medrivia@gmail.com"
}

# Numeric comparison of dotted versions: true if a is strictly newer than b
# (2.0.5 > 1.18.31, 2.0.10 > 2.0.9). Unparseable versions are never newer,
# so a bad comparison can never trigger a downgrade.
def ver_gt [a: string, b: string] {
	let pa = (try { $a | split row '.' | each { into int } } catch { null })
	let pb = (try { $b | split row '.' | each { into int } } catch { null })
	if $pa == null or $pb == null {
		return false
	}
	let la = ($pa | length)
	let lb = ($pb | length)
	let min = ([$la, $lb] | math min)
	let cmp = (
		seq 0 ($min - 1)
		| each {|i|
			if (($pa | get $i) > ($pb | get $i)) { 1 } else if (($pa | get $i) < ($pb | get $i)) { -1 } else { 0 }
		}
		| where { $in != 0 }
		| first
		| default 0
	)
	if $cmp != 0 {
		return ($cmp > 0)
	}
	# Equal on the common prefix: longer wins only with a nonzero extra part
	# (2.0.1 > 2.0, but 2.0.0 == 2.0)
	let ta = ($pa | skip $min)
	let tb = ($pb | skip $min)
	let ta_pos = (if ($ta | is-empty) { false } else { $ta | any {|x| $x > 0 } })
	let tb_pos = (if ($tb | is-empty) { false } else { $tb | any {|x| $x > 0 } })
	$ta_pos and (not $tb_pos)
}

# Main entry point with optional --dry-run flag
# Main entry point with optional --dry-run flag
def main [--dry-run] {
	print $"::group::📦 AUR Package Updater"
	print $"🕐 Started at: (date now | format date '%Y-%m-%d %H:%M:%S')"
	print ""

	# Load packages configuration from script's directory
	let script_dir = $env.FILE_PWD
	print $"📂 Script directory: ($script_dir)"
	print ""

	print "::endgroup::"

	print $"::group::📋 Loading configuration"
	print $"📖 Reading update.jsonc..."
	let packages = (open --raw $"($script_dir)/update.jsonc" | from json)
	print $"✅ Found ($packages | length) package\(s) to check"
	print "::endgroup::"

	# Temporary file to track updated packages
	let updated_file = (mktemp)
	print $"📝 Using temp file: ($updated_file)"
	print ""

	# Run update process
	update_packages $packages $dry_run $updated_file $script_dir

	# Cleanup
	print "::group::🧹 Cleanup"
	if ($updated_file | path exists) {
		rm -f $updated_file
		print $"🗑️  Removed temp file: ($updated_file)"
	}
	print "✅ Cleanup complete"
	print "::endgroup::"

	print ""
	print $"🕐 Finished at: (date now | format date '%Y-%m-%d %H:%M:%S')"
}

def update_packages [packages: list, dry_run: bool, updated_file: path, script_dir: path] {
	# Save original directory - we'll return here after each package
	let original_dir = $env.PWD

	# Ensure we have packages to process
	if ($packages | length) == 0 {
		print "⚠️ No packages found in update.jsonc"
		return
	}

	mut success_count = 0
	mut skip_count = 0
	mut error_count = 0

	for pkg in $packages {
		let pkgname = $pkg.pkgname
		let pkg_url = if ('url' in $pkg) { $pkg.url } else { null }
		let update_script = if ('update' in $pkg) { $pkg.update } else { null }
		let pkg_dir = $pkg.path

		print $"::group::🔍 ($pkgname)"
		print $"📦 Package: ($pkgname)"
		if $pkg_url != null {
			print $"🔗 URL: ($pkg_url)"
		}
		if $update_script != null {
			print $"🔧 Update script: ($update_script)"
		}
		print $"📂 Directory: ($pkg_dir)"
		print ""

		# Check if directory exists
		if not ($pkg_dir | path exists) {
			print $"::error::❌ Directory not found: ($pkg_dir)"
			$error_count = $error_count + 1
			print "::endgroup::"
			continue
		}
		print "✅ Directory exists"

		# Move to package directory
		cd $pkg_dir
		print $"📍 Working in: (pwd)"
		print ""

		# Get current pkgver from PKGBUILD
		print "🔍 Reading current version from PKGBUILD..."
		let current_ver = (
			open PKGBUILD 
			| lines 
			| where { $in | str starts-with "pkgver=" }
			| first
			| parse "pkgver={val}"
			| get val
			| first
			| str replace -a '"' ''
			| str trim
		)
		print $"   Current version: ($current_ver)"
		print ""

		# Detect git provider and fetch latest release
		print "🌐 Checking remote repository for updates..."
		let new_ver = (
			if $update_script != null {
				# Use custom update script
				let script_path = $"($script_dir)/updates/($update_script).nu"

				if not ($script_path | path exists) {
					print $"::error::❌ Update script not found: ($script_path)"
					cd $original_dir
					$error_count = $error_count + 1
					print "::endgroup::"
					continue
				}

				let result = (^nu $script_path $pkgname | complete)

				if $result.exit_code != 0 {
					print $"::error::❌ Update script failed with exit code ($result.exit_code)"
					cd $original_dir
					$error_count = $error_count + 1
					print "::endgroup::"
					continue
				}

				if ($result.stdout | str trim) == "" {
					print $"::error::❌ Update script returned empty output"
					cd $original_dir
					$error_count = $error_count + 1
					print "::endgroup::"
					continue
				}

				($result.stdout | str trim)
			} else if ($pkg_url | str contains "github.com") {
				let github_repo = ($pkg_url | str replace -r "^https://github.com/" "")
				let gh_headers = if ($env.GITHUB_API_TOKEN? | is-empty) { {} } else {
					{ Authorization: $"Bearer ($env.GITHUB_API_TOKEN)", Accept: "application/vnd.github+json", X-GitHub-Api-Version: "2022-11-28" }
				}
				print $"   🔑 Using authenticated GitHub API: ($gh_headers != {})"


				# Turn a tag into a bare dotted version (v2.0.5 -> 2.0.5)
				let to_ver = {|t| $t | str replace -r '^[^0-9]+' '' | split row ' ' | get 0 }

				# Candidates in order of preference: newest stable release, then
				# newest release of any kind (pre-releases), then the newest git
				# tag newer than the installed version. The tag fallback covers
				# repos that publish tags without creating GitHub Releases
				# (e.g. anomalyco/opencode, whose v2.x ships tags only).
				mut chosen_ver = ""

				# 1) Stable release
				let latest_api = $"https://api.github.com/repos/($github_repo)/releases/latest"
				print $"   Trying stable releases: ($latest_api)"

				let latest_result = (
					try {
						http get -H $gh_headers $latest_api
					} catch { |err|
						print $"   ::warning::⚠️ Stable releases request failed: ($err.msg)"
						{ tag_name: "null" }
					}
				)

				if $latest_result.tag_name != "null" {
					$chosen_ver = (do $to_ver $latest_result.tag_name)
					print $"   Latest release: ($latest_result.tag_name) → version: ($chosen_ver)"
				}

				# 2) No stable release: newest release of any kind (pre-releases included)
				if $chosen_ver == "" {
					print "   ℹ️ No stable release found, checking pre-releases..."
					let all_api = $"https://api.github.com/repos/($github_repo)/releases"
					print $"   API URL: ($all_api)"

					let all_result = (
						try {
							http get -H $gh_headers $all_api
						} catch { |err|
							print $"   ::warning::⚠️ Pre-release list request failed: ($err.msg)"
							[]
						}
					)

					if ($all_result | length) > 0 {
						$chosen_ver = (do $to_ver ($all_result | get 0.tag_name))
						print $"   Latest release \(any\): ($all_result | get 0.tag_name) → version: ($chosen_ver)"
					}
				}

				# 3) Release candidate is not newer than the current version:
				#    scan git tags for something newer (tag-only repos)
				# Scan only when the candidate is strictly older than the current
				# version; an equal candidate is already up to date.
				if ($chosen_ver == "") or (ver_gt $current_ver $chosen_ver) {
					let tags_api = $"https://api.github.com/repos/($github_repo)/tags?per_page=100"
					print $"   No newer release, scanning tags: ($tags_api)"

					let tags_result = (
						try {
							http get -H $gh_headers $tags_api
						} catch { |err|
							print $"   ::warning::⚠️ Tags request failed: ($err.msg)"
							[]
						}
					)

					let newer_tags = (
						$tags_result
						| get name
						| each {|t| do $to_ver $t }
						| where {|v| ($v =~ '^\d+(\.\d+)+$') and (ver_gt $v $current_ver) }
					)

					if ($newer_tags | is-not-empty) {
						$chosen_ver = ($newer_tags | reduce --fold "0" {|acc, v| if (ver_gt $v $acc) { $v } else { $acc } })
						print $"   Newest tag newer than ($current_ver): ($chosen_ver)"
					}
				}

				if $chosen_ver == "" {
					print $"::warning::⚠️ No releases found for ($pkgname)"
					cd $original_dir
					$skip_count = $skip_count + 1
					print "::endgroup::"
					continue
				}

				$chosen_ver
			} else if ($pkg_url | str contains "crates.io/crates/") {
				let crate_name = ($pkg_url | str replace -r '^.*/crates/' '' | str trim -c '/')
				let api_url = $"https://crates.io/api/v1/crates/($crate_name)"
				print $"   API URL: ($api_url)"

				let resp = (
					try {
						http get -H { User-Agent: "alarm-update-check (medrivia@gmail.com)" } $api_url
					} catch { |err|
						print $"   ::warning::⚠️ crates.io request failed: ($err.msg)"
						{ crate: { max_stable_version: null, max_version: null } }
					}
				)

				let ver = ($resp.crate.max_stable_version? | default $resp.crate.max_version?)
				if ($ver | is-empty) {
					print $"::warning::⚠️ No versions found for crate ($crate_name)"
					cd $original_dir
					$skip_count = $skip_count + 1
					print "::endgroup::"
					continue
				}
				print $"   Latest crate version: ($ver)"
				$ver
			} else if ($pkg_url | str contains "gitlab.com") {
				print "::warning::⚠️ GitLab support is untested - skipping"
				cd $original_dir
				$skip_count = $skip_count + 1
				print "::endgroup::"
				continue
			} else if ($pkg_url | str contains "codeberg.org") {
				print "::warning::⚠️ Codeberg support is untested - skipping"
				cd $original_dir
				$skip_count = $skip_count + 1
				print "::endgroup::"
				continue
			} else if $pkg_url != null {
				print $"::error::❌ Unsupported URL: ($pkg_url)"
				cd $original_dir
				$error_count = $error_count + 1
				print "::endgroup::"
				continue
			} else {
				print $"::error::❌ No url or update script specified"
				cd $original_dir
				$error_count = $error_count + 1
				print "::endgroup::"
				continue
			}
		)
		print ""

		# Check if version was successfully retrieved
		if $new_ver == null {
			cd $original_dir
			$error_count = $error_count + 1
			print "::endgroup::"
			continue
		}

		# Check if already up to date (semver-aware: never downgrade)
		if not (ver_gt $new_ver $current_ver) {
			if $new_ver == $current_ver {
				print $"✅ Already up to date: ($current_ver)"
			} else {
				print $"✅ Skipping downgrade: found ($new_ver), current ($current_ver) is newer"
			}
			cd $original_dir
			$skip_count = $skip_count + 1
			print "::endgroup::"
			continue
		}

		print $"📈 Update available: ($current_ver) → ($new_ver)"
		print ""

		# Bump version in PKGBUILD
		print "📝 Updating PKGBUILD..."
		if $dry_run {
			print $"   [DRY-RUN] Would update pkgver to ($new_ver)"
		} else {
			let pkgbuild_path = $"($env.PWD)/PKGBUILD"
			let content = (
				open $pkgbuild_path
				| lines
				| each { |line|
					if ($line | str starts-with "pkgver=") {
						$"pkgver=($new_ver)"
					} else {
						$line
					}
				}
				| str join "\n"
			)
			$"($content)\n" | save -f $pkgbuild_path
			print $"   ✅ PKGBUILD updated - saved to ($pkgbuild_path)"
		}
		print ""

		# Update checksums and .SRCINFO
		print "🔧 Updating checksums and .SRCINFO..."
		if $dry_run {
			print "   [DRY-RUN] Would run: updpkgsums && makepkg --printsrcinfo > .SRCINFO"
		} else {
			print $"   Working directory: ($env.PWD)"
			print "   Running updpkgsums..."
			let updpkgsums_result = (^updpkgsums | complete)
			if $updpkgsums_result.exit_code != 0 {
				print $"::error::❌ updpkgsums failed: ($updpkgsums_result.stderr)"
				cd $original_dir
				$error_count = $error_count + 1
				print "::endgroup::"
				continue
			}
			print "   ✅ Checksums updated"

			print "   Generating .SRCINFO..."
			let srcinfo_result = try {
				let output = ^makepkg --printsrcinfo
				$output | save -f .SRCINFO
				{ exit_code: 0, stderr: "" }
			} catch { |err|
				{ exit_code: 1, stderr: $err.msg }
			}
			if $srcinfo_result.exit_code != 0 {
				print $"::error::❌ makepkg --printsrcinfo failed: ($srcinfo_result.stderr)"
				cd $original_dir
				$error_count = $error_count + 1
				print "::endgroup::"
				continue
			}
			print "   ✅ .SRCINFO generated"
		}
		print ""

		# Push to AUR
		# print "🚀 Pushing to AUR..."
		# if $dry_run {
		# 	print $"   [DRY-RUN] Would clone, copy all files, commit, and push to aur@aur.archlinux.org:($pkgname).git"
		# } else {
		# 	let temp_dir = (mktemp -d)
		# 	print $"   Cloning AUR repo to ($temp_dir)..."
		#
		# 	let clone_result = (
		# 		^git clone $"ssh://aur@aur.archlinux.org/($pkgname).git" $temp_dir
		# 		| complete
		# 	)
		#
		# 	if $clone_result.exit_code != 0 {
		# 		print $"::error::❌ Failed to clone AUR repo: ($clone_result.stderr)"
		# 		rm -rf $temp_dir
		# 		cd $original_dir
		# 		$error_count = $error_count + 1
		# 		print "::endgroup::"
		# 		continue
		# 	}
		# 	print "   ✅ Cloned AUR repository"
		#
		# 	# Copy all files from package directory to temp dir (including hidden files like .SRCINFO)
		# 	print "   Copying all files from package directory..."
		# 	# Use rsync to properly handle hidden files
		# 	^rsync -av --exclude='.git' ./ $"($temp_dir)/"
		# 	print "   ✅ Files copied"
		# 	# Work in temp dir
		# 	cd $temp_dir
		#
		# 	# Configure git
		# 	print $"   Configuring git user: ($USER.NAME)"
		# 	git config user.name $USER.NAME
		# 	git config user.email $USER.EMAIL
		#
		# 	# Commit and push
		# 	print "   Committing changes..."
		# 	# Add all files to commit
		# 	git add -A
		# 	let commit_result = (git commit -m $"chore: update ($pkgname) to ($new_ver)" | complete)
		#
		# 	if $commit_result.exit_code == 0 {
		# 		print "   ✅ Committed: ($commit_result.stdout | str trim)"
		#
		# 		print "   Pushing to AUR..."
		# 		let push_result = (git push origin master | complete)
		# 		if $push_result.exit_code != 0 {
		# 			print $"::error::❌ Failed to push to AUR: ($push_result.stderr)"
		# 		} else {
		# 			print "   ✅ Pushed to AUR"
		# 		}
		# 	} else {
		# 		print "   ℹ️ No changes to commit (already up to date in AUR)"
		# 	}
		#
		# 	# Clean up temp dir and return to original
		# 	cd $original_dir
		# 	rm -rf $temp_dir
		# 	print "   🗑️  Cleaned up temp directory"
		# }
		# print ""

		# Track updated package
		$"($pkgname)\n" | save -a $updated_file
		$success_count = $success_count + 1

		# Always return to original directory for next iteration
		cd $original_dir
		print "::endgroup::"
	}

	print ""
	print "::group::📊 Summary"
	print $"✅ Updated: ($success_count)"
	print $"⏭️  Skipped: ($skip_count)"
	print $"❌ Errors: ($error_count)"
	print "::endgroup::"

	# Commit changes to GitHub repo
	print ""
	print "::group::📤 Committing changes to GitHub"

	let updated_packages = (
		if ($updated_file | path exists) and (open $updated_file | lines | length) > 0 {
			open $updated_file | lines
		} else {
			[]
		}
	)

	if ($updated_packages | length) > 0 {
		let package_list = ($updated_packages | str join ", ")
		print $"📦 Packages to commit: ($package_list)"

		if $dry_run {
			print $"[DRY-RUN] Would commit and push to GitHub"
		} else {
			print "   Configuring git..."
			git config user.name $USER.NAME
			git config user.email $USER.EMAIL

			print "   Adding files..."
			print "   Adding updated tracked files..."
			git add -u

			print "   Committing..."
			let commit_result = (
				git commit -m $"chore: update AUR packages ($package_list)"
				| complete
			)

			if $commit_result.exit_code == 0 {
				print $"   ✅ Committed: ($commit_result.stdout | str trim)"

				print "   Pushing to GitHub..."
				let push_result = (git push | complete)
				if $push_result.exit_code != 0 {
					print $"::error::❌ Failed to push to GitHub: ($push_result.stderr)"
				} else {
					print "   ✅ Pushed to GitHub"
				}
			} else {
				print "   ℹ️ No changes to commit to GitHub"
			}
		}
	} else {
		print "✅ No updates needed - nothing to commit"
	}
	print "::endgroup::"
}
