#!/bin/bash
set -euo pipefail

# Configuration
PACKAGER='mdrv <mdrv@users.noreply.github.com>'
OUTPUT_DIR="/work"
PACKAGES_DIR="/home/builder/packages"
BUILDER_UID="1000"
BUILDER_GID="1000"

# Disable pacman sandbox (Landlock not supported in container)
echo "Configuring pacman..."
sed -i 's|^#\?DisableSandbox.*|DisableSandbox|' /etc/pacman.conf || echo "DisableSandbox" >> /etc/pacman.conf

# Create builder user
echo "Setting up builder user..."
useradd -m -u ${BUILDER_UID} builder 2>/dev/null || true

# Configure sudo: allow builder to run pacman without password
echo "Allowing builder to run pacman without password..."
echo "builder ALL=(ALL) NOPASSWD: /usr/bin/pacman" > /etc/sudoers.d/builder
chmod 440 /etc/sudoers.d/builder

# Import official Arch Linux ARM keyring (required for package builds)
echo "Importing Arch Linux ARM keyring..."
pacman-key --init
pacman-key --populate archlinuxarm

# Initialize pacman and install basic build dependencies (run as root)
echo "Initializing pacman and installing dependencies..."
pacman -Syu --noconfirm
pacman -S --noconfirm --needed meson scdoc wayland-protocols

# Configure makepkg
echo "PACKAGER=\"${PACKAGER}\"" >> /etc/makepkg.conf

# Prepare packages directory
echo "Preparing packages directory..."
mkdir -p "${OUTPUT_DIR}/aarch64"
chown -R builder:builder "${OUTPUT_DIR}/aarch64"
cp -r "${OUTPUT_DIR}/packages" /home/builder/
chown -R builder:builder /home/builder/packages

# Build packages (unsigned, output directly to aarch64 via env var)
echo "Building packages..."
cd "${PACKAGES_DIR}"
BUILD_FAILED=0

for pkgdir in */; do
  echo "::group::Building $pkgdir"
  cd "$pkgdir"

  echo "DEBUG: Current directory: $(pwd)"
  echo "DEBUG: PKGDEST env: ${PKGDEST:-not set}"
  echo "DEBUG: OUTPUT_DIR: ${OUTPUT_DIR}/aarch64"
  echo "DEBUG: Listing files before build:"
  ls -la || true
  echo "DEBUG: makepkg config for PKGDEST:"
  sudo -u builder bash -c 'makepkg --showconfig | grep -E "^PKGDEST|PACKAGER" | head -5' || true

  if ! sudo -u builder bash -c "PKGDEST='${OUTPUT_DIR}/aarch64' makepkg --needed --syncdeps --noconfirm -f"; then
    echo "::warning::Failed to build $pkgdir"
    BUILD_FAILED=1
  fi

  echo "DEBUG: Listing files after build (in pkgdir):"
  ls -la || true
  echo "DEBUG: Listing files in OUTPUT_DIR/aarch64:"
  ls -la "${OUTPUT_DIR}/aarch64" || true
  echo "DEBUG: Searching for any .pkg.tar.zst files on system:"
  sudo -u builder find / -name "*.pkg.tar.zst" 2>/dev/null || true

  cd ..
  echo "::endgroup::"
done

# DEBUG: Final filesystem check
echo "DEBUG: Final filesystem check"
echo "DEBUG: Contents of ${OUTPUT_DIR}/aarch64:"
ls -la "${OUTPUT_DIR}/aarch64" || true
echo "DEBUG: All .pkg.tar.zst files in ${OUTPUT_DIR}:"
find "${OUTPUT_DIR}" -name "*.pkg.tar.zst" 2>/dev/null || echo "None found"
echo "DEBUG: All .pkg.tar.zst files in ${PACKAGES_DIR}:"
find "${PACKAGES_DIR}" -name "*.pkg.tar.zst" 2>/dev/null || echo "None found"
echo "DEBUG: Permissions on ${OUTPUT_DIR}/aarch64:"
ls -ld "${OUTPUT_DIR}/aarch64" || true

# Create repository database (unsigned)
echo "Creating repository database..."
cd "${OUTPUT_DIR}/aarch64"
if [ -n "$(ls *.pkg.tar.zst 2>/dev/null)" ]; then
  repo-add mdrv.db.tar.gz *.pkg.tar.zst
else
  echo "No packages built, creating empty database files"
  touch mdrv.db.tar.gz
  touch mdrv.files.tar.gz
fi

# Generate index.html
echo "Generating index.html..."
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
sed "s/BUILD_DATE/${BUILD_DATE}/" "${OUTPUT_DIR}/index.html.template" > "${OUTPUT_DIR}/aarch64/index.html"

# Fix permissions
echo "Fixing permissions..."
chown -R $(id -u):$(id -g) "${OUTPUT_DIR}/aarch64"

# Exit with error if any build failed
if [ "$BUILD_FAILED" -eq 1 ]; then
  echo "::error::One or more packages failed to build"
  exit 1
fi

echo "Build complete!"
