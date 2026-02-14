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

# Import official Arch Linux ARM keyring (required for package builds)
echo "Importing Arch Linux ARM keyring..."
pacman-key --init
pacman-key --populate archlinuxarm

# Initialize pacman and install build dependencies (run as root, then build as builder)
echo "Initializing pacman and installing dependencies..."
pacman -Syu --noconfirm
pacman -S --noconfirm --needed meson scdoc wayland-protocols

# Configure makepkg
echo "PACKAGER=\"${PACKAGER}\"" >> /etc/makepkg.conf

# Prepare packages directory
echo "Preparing packages directory..."
cp -r "${OUTPUT_DIR}/packages" /home/builder/
chown -R builder:builder /home/builder/packages

# Build packages (unsigned)
echo "Building packages..."
cd "${PACKAGES_DIR}"
BUILD_FAILED=0

for pkgdir in */; do
  echo "::group::Building $pkgdir"
  cd "$pkgdir"

  if ! sudo -u builder makepkg --needed --syncdeps --noconfirm -f; then
    echo "::warning::Failed to build $pkgdir"
    BUILD_FAILED=1
  fi

  cd ..
  echo "::endgroup::"
done

# Prepare output directory
echo "Preparing output directory..."
mkdir -p "${OUTPUT_DIR}/aarch64"
find "${PACKAGES_DIR}" -name "*.pkg.tar.zst" -exec cp {} "${OUTPUT_DIR}/aarch64/" \;

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
