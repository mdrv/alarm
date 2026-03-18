#!/usr/bin/env nu

# AUR package update script - Nushell version
# Updates packages defined in update.jsonc

const USER = {
	NAME: "Umar Alfarouk"
	EMAIL: "medrivia@gmail.com"
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
	update_packages $packages $dry_run $updated_file

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

def update_packages [packages: list, dry_run: bool, updated_file: path] {
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
		let repo_url = $pkg.repo
		let pkg_dir = $pkg.path

		print $"::group::🔍 ($pkgname)"
		print $"📦 Package: ($pkgname)"
		print $"🔗 Repository: ($repo_url)"
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
			if ($repo_url | str contains "github.com") {
				let github_repo = ($repo_url | str replace -r "^https://github.com/" "")

				# Try stable releases first
				let latest_api = $"https://api.github.com/repos/($github_repo)/releases/latest"
				print $"   Trying stable releases: ($latest_api)"

				let latest_result = (
					try {
						http get $latest_api
					} catch { |err|
						{ tag_name: "null" }
					}
				)

				# If no stable release, try all releases (includes pre-releases)
				let result = if $latest_result.tag_name == "null" {
					print "   ℹ️ No stable release found, checking pre-releases..."
					let all_api = $"https://api.github.com/repos/($github_repo)/releases"
					print $"   API URL: ($all_api)"

					let all_result = (
						try {
							http get $all_api
						} catch { |err|
							[]
						}
					)

					if ($all_result | length) == 0 {
						{ tag_name: "null" }
					} else {
						{ tag_name: ($all_result | get 0.tag_name) }
					}
				} else {
					print $"   API URL: ($latest_api)"
					$latest_result
				}

				if $result.tag_name == "null" {
					print $"::warning::⚠️ No releases found for ($pkgname)"
					cd $original_dir
					$skip_count = $skip_count + 1
					print "::endgroup::"
					continue
				}

				let ver = ($result.tag_name | str replace -r '^[^0-9]+' "" | split row ' ' | get 0)
				print $"   Latest release: ($result.tag_name) → version: ($ver)"
				$ver
			} else if ($repo_url | str contains "gitlab.com") {
				print "::warning::⚠️ GitLab support is untested - skipping"
				cd $original_dir
				$skip_count = $skip_count + 1
				print "::endgroup::"
				continue
			} else if ($repo_url | str contains "codeberg.org") {
				print "::warning::⚠️ Codeberg support is untested - skipping"
				cd $original_dir
				$skip_count = $skip_count + 1
				print "::endgroup::"
				continue
			} else {
				print $"::error::❌ Unsupported git provider: ($repo_url)"
				cd $original_dir
				$error_count = $error_count + 1
				print "::endgroup::"
				continue
			}
		)
		print ""

		# Check if already up to date
		if $new_ver == $current_ver {
			print $"✅ Already up to date: ($current_ver)"
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
