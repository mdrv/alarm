#!/usr/bin/env nu

# Arch Linux ARM Package Builder - Nushell version
# Reads configuration from update.jsonc and builds/copies packages

const PACKAGER = "Umar Alfarouk <medrivia@gmail.com>"
const OUTPUT_DIR = "/work"
const PACKAGES_DIR = "/home/builder/packages"
const ARCH_DIR = $"($OUTPUT_DIR)/aarch64"

# Get host UID/GID for proper file ownership
let host_uid = ($env.HOST_UID? | default "1001")
let host_gid = ($env.HOST_GID? | default "1001")

print $"::group::🔧 Setup"
print "Cleaning up any previous builds..."
rm -rf $ARCH_DIR

print $"Host UID: ($host_uid), Host GID: ($host_gid)"

# Disable pacman sandbox (Landlock not supported in container)
print "Configuring pacman..."
try {
	^sed -i 's|^#\?DisableSandbox.*|DisableSandbox|' /etc/pacman.conf
} catch {
	echo "DisableSandbox" | save -af /etc/pacman.conf
}

# Create builder user with same UID as host to avoid permission issues
print "Setting up builder user..."
try {
	^useradd -m -u $host_uid builder
} catch {}

# Configure sudo: allow builder to run pacman without password
print "Allowing builder to run pacman without password..."
"builder ALL=(ALL) NOPASSWD: /usr/bin/pacman" | save -f /etc/sudoers.d/builder
^chmod 440 /etc/sudoers.d/builder

# Import official Arch Linux ARM keyring
print "Importing Arch Linux ARM keyring..."
^pacman-key --init
^pacman-key --populate archlinuxarm

# Upgrade system packages
^pacman -Syu --noconfirm

# Configure makepkg
$"PACKAGER=\"($PACKAGER)\"" | save -a /etc/makepkg.conf

# Prepare directories
print "Preparing directories..."
mkdir $ARCH_DIR
^chown -R builder:builder $OUTPUT_DIR
^cp -r $"($OUTPUT_DIR)/packages" /home/builder/packages
^chown -R builder:builder /home/builder/packages

# Load package configuration from update.jsonc
print "Loading package configuration from update.jsonc..."
let update_jsonc = $"($OUTPUT_DIR)/update.jsonc"

if not ($update_jsonc | path exists) {
	print $"::error::update.jsonc not found at ($update_jsonc)"
	exit 1
}

let packages = (
	open --raw $update_jsonc
	| from json
	| sort-by priority  # Sort by priority (lower = built first)
)

print $"Found ($packages | length) package(s)"
print $"Packages: ($packages | get pkgname | str join ', ')"
print "::endgroup::"

# Separate into build and prebuilt lists
let build_packages = ($packages | where build == true)
let prebuilt_packages = ($packages | where build == false)

print ""
print $"::group::📦 Prebuilt packages: ($prebuilt_packages | length)"
print $"Prebuilt: ($prebuilt_packages | get pkgname | str join ', ')"
print "::endgroup::"

print ""
print $"::group::🔨 Packages to build: ($build_packages | length)"
print $"Build: ($build_packages | get pkgname | str join ', ')"
print "::endgroup::"

# Copy prebuilt packages first
mut build_failed = false

for pkg in $prebuilt_packages {
	let pkgname = $pkg.pkgname
	let pkgdir = $"($PACKAGES_DIR)/($pkgname)"
	
	print $"::group::📋 Copying prebuilt: ($pkgname)"
	
	if not ($pkgdir | path exists) {
		print $"::warning::Package directory not found: ($pkgdir)"
		print "::endgroup::"
		continue
	}
	
	# Find and copy prebuilt .pkg.tar.zst files
	let prebuilt_files = (
		ls $pkgdir
		| where name =~ '\.pkg\.tar\.(zst|xz)$'
		| get name
	)
	
	if ($prebuilt_files | length) == 0 {
		print $"::warning::No prebuilt package found in ($pkgdir)"
		print "::endgroup::"
		continue
	}
	
	for file in $prebuilt_files {
		print $"  Copying: ($file)"
		cp $file $ARCH_DIR
	}
	
	print "::endgroup::"
}

# Build packages in priority order
for pkg in $build_packages {
	let pkgname = $pkg.pkgname
	let pkgdir = $"($PACKAGES_DIR)/($pkgname)"
	
	print $"::group::🔨 Building: ($pkgname)"
	
	if not ($pkgdir | path exists) {
		print $"::warning::Package directory not found: ($pkgdir)"
		print "::endgroup::"
		continue
	}
	
	cd $pkgdir
	
	# Use PKGDEST environment variable to output to aarch64 directory
	let result = (
		^sudo -u builder bash -c $"PKGDEST='($ARCH_DIR)' makepkg --needed --syncdeps --noconfirm -f"
		| complete
	)
	
	if $result.exit_code != 0 {
		print $"::warning::Failed to build ($pkgname)"
		$build_failed = true
		print "::endgroup::"
		continue
	}
	
	# Install the newly built package so dependent packages can find it
	let pkg_files = (
		ls $ARCH_DIR
		| where name =~ $"\($pkgname)-.*\\.pkg\\.tar\\.(zst|xz)$"
		| get name
		| first?
	)
	
	if ($pkg_files | is-not-empty) {
		^pacman -U --noconfirm $pkg_files
	}
	
	cd $PACKAGES_DIR
	print "::endgroup::"
}

# Check if packages are in aarch64 directory
print ""
print "::group::📊 Build Results"
print $"Checking ($ARCH_DIR) for packages:"
^ls -la $ARCH_DIR
print "::endgroup::"

# Create repository database
print ""
print "::group::📦 Creating repository database"
cd $ARCH_DIR

let pkg_files = (
	ls $ARCH_DIR
	| where name =~ '\.pkg\.tar\.(zst|xz)$'
	| get name
)

if ($pkg_files | length) > 0 {
	print $"Creating database with ($pkg_files | length) packages..."
	^repo-add -R mdrv.db.tar.gz ...$pkg_files
} else {
	print "No packages found to build database"
}
print "::endgroup::"

# Fix permissions - chown to host user so files are accessible outside container
print ""
print "::group::🔧 Fixing permissions"
print $"Fixing permissions to host user ($host_uid):($host_gid)..."
^chown -R $"($host_uid):($host_gid)" $"($OUTPUT_DIR)/aarch64"
print "::endgroup::"

# Exit with error if any build failed
if $build_failed {
	print ""
	print "::error::One or more packages failed to build"
	exit 1
}

print ""
print "✅ Build complete!"
