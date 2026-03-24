#!/usr/bin/env nu

use std log

# Arch Linux ARM Package Builder - Nushell version
# Reads configuration from update.jsonc and builds/copies packages

const PACKAGER = "Umar Alfarouk <medrivia@gmail.com>"
const OUTPUT_DIR = "/work"
const PACKAGES_DIR = "/home/builder/packages"
const PREBUILT_DIR = "/work/prebuilt"
const ARCH_DIR = "/work/aarch64"

log info "Starting Arch Linux ARM Package Builder"

# Get host UID/GID for proper file ownership
let host_uid = ($env.HOST_UID? | default "1001")
let host_gid = ($env.HOST_GID? | default "1001")

log info $"Host UID: ($host_uid), Host GID: ($host_gid)"

# Disable pacman sandbox (Landlock not supported in container)
log info "Configuring pacman..."
try {
	^sed -i 's|^#\?DisableSandbox.*|DisableSandbox|' /etc/pacman.conf
} catch {
	echo "DisableSandbox" | save -af /etc/pacman.conf
}

# Create builder user with same UID as host to avoid permission issues
log info "Setting up builder user..."
try {
	^useradd -m -u $host_uid builder
} catch {}

# Configure sudo: allow builder to run pacman without password
log info "Configuring sudo for builder..."
"builder ALL=(ALL) NOPASSWD: /usr/bin/pacman" | save -f /etc/sudoers.d/builder
^chmod 440 /etc/sudoers.d/builder

# Import official Arch Linux ARM keyring
log info "Importing Arch Linux ARM keyring..."
^pacman-key --init
^pacman-key --populate archlinuxarm

# Upgrade system packages
log info "Upgrading system packages..."
^pacman -Syu --noconfirm

# Configure makepkg
log info "Configuring makepkg..."
$"\nPACKAGER=\"($PACKAGER)\"" | save -a /etc/makepkg.conf

# Prepare directories
log info "Preparing directories..."
mkdir $ARCH_DIR
^chown -R builder:builder $OUTPUT_DIR
^cp -r $"($OUTPUT_DIR)/packages" /home/builder/packages
^chown -R builder:builder /home/builder/packages

# Load package configuration from update.jsonc
log info "Loading package configuration from update.jsonc..."

let update_jsonc = $"($OUTPUT_DIR)/update.jsonc"

if not ($update_jsonc | path exists) {
	log error $"update.jsonc not found at ($update_jsonc)"
	exit 1
}

let packages = (
	open --raw $update_jsonc
	| from json
	| sort-by priority
)

log info $"Found ($packages | length) package\(s)"
log info $"Packages: ($packages | get pkgname | str join ', ')"

# Separate into build and prebuilt lists
let build_packages = ($packages | where build == true)
let prebuilt_packages = ($packages | where build == false)

log info $"Prebuilt packages: ($prebuilt_packages | length)"
log info $"Packages to build: ($build_packages | length)"

# Copy prebuilt packages from prebuilt directory
mut build_failed = false

if ($PREBUILT_DIR | path exists) {
	log info $"Copying prebuilt packages from ($PREBUILT_DIR)..."
	
	let prebuilt_files = (
		ls $PREBUILT_DIR
		| where name =~ '\.pkg\.tar\.(zst|xz)$'
	)
	
	if ($prebuilt_files | length) > 0 {
		for file in $prebuilt_files {
			log info $"  Copying: ($file.name)"
			cp $file.name $ARCH_DIR
		}
	} else {
		log warning $"No prebuilt files found in ($PREBUILT_DIR)"
	}
} else {
	log warning $"Prebuilt directory not found: ($PREBUILT_DIR)"
}

# Build packages in priority order
for pkg in $build_packages {
	let pkgname = $pkg.pkgname
	let pkgdir = $"($PACKAGES_DIR)/($pkgname)"
	
	log info $"Building: ($pkgname)"
	
	if not ($pkgdir | path exists) {
		log warning $"Package directory not found: ($pkgdir)"
		continue
	}
	
	cd $pkgdir
	
	# Build using makepkg as builder user
	let result = (
		^sudo -u builder bash -c $"PKGDEST='($ARCH_DIR)' makepkg --needed --syncdeps --noconfirm -f"
		| complete
	)
	
	if $result.exit_code != 0 {
		log warning $"Failed to build ($pkgname)"
		$build_failed = true
		cd $PACKAGES_DIR
		continue
	}
	
	# Install the newly built package so dependent packages can find it
	let pattern = $pkgname + '-.*\.pkg\.tar\.(zst|xz)$'
	let pkg_files = (
		ls $ARCH_DIR
		| where name =~ $pattern
		| get name
	)
	
	if ($pkg_files | is-not-empty) and (($pkg_files | length) > 0) {
		log info $"Installing ($pkg_files) for dependent packages..."
		try {
			^pacman -U --noconfirm ...$pkg_files
		} catch {
			log warning $"Failed to install ($pkg_files)"
		}
	}
	
	cd $PACKAGES_DIR
}

# Check if packages are in aarch64 directory
log info "Build results:"
^ls -la $ARCH_DIR

# Create repository database
log info "Creating repository database..."
cd $ARCH_DIR

let pkg_files = (
	ls
	| where name =~ '\.pkg\.tar\.(zst|xz)$'
	| get name
)

if ($pkg_files | length) > 0 {
	log info $"Creating database with ($pkg_files | length) packages..."
	^repo-add -R mdrv.db.tar.gz ...$pkg_files
} else {
	log warning "No packages found to build database"
}

# Fix permissions
log info $"Fixing permissions to host user ($host_uid):($host_gid)..."
^chown -R $"($host_uid):($host_gid)" $ARCH_DIR

# Exit with error if any build failed
if $build_failed {
	log error "One or more packages failed to build"
	exit 1
}

log info "Build complete!"
