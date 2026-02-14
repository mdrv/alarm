#!/bin/bash
set -euo pipefail

# Configuration
PACKAGER='mdrv <mdrv@users.noreply.github.com>'
OUTPUT_DIR="/work"
PACKAGES_DIR="/home/builder/packages"
BUILDER_UID="1000"
BUILDER_GID="1000"

# Official Arch Linux ARM Build System key
ARCH_ARM_KEY="68B3537F39A313B3E574D06777193F152BDBE6A6"

# Create builder user
echo "Setting up builder user..."
useradd -m -u ${BUILDER_UID} builder 2>/dev/null || true

# Configure makepkg (disable landlock via environment variable)
echo "Configuring makepkg..."
export BUILDENV="!landlock"
export PACKAGER="$PACKAGER"
export GPGKEY="$ARCH_ARM_KEY"

# Import official Arch Linux ARM Build System key for signing
echo "Importing Arch Linux ARM Build System key..."
pacman-key --init
pacman-key --populate archlinuxarm

# Initialize pacman and install build dependencies
echo "Initializing pacman and installing dependencies..."
pacman -Sy --noconfirm
pacman -S --noconfirm --needed meson scdoc wayland-protocols

# Prepare packages directory
echo "Preparing packages directory..."
cp -r "${OUTPUT_DIR}/packages" /home/builder/
chown -R builder:builder /home/builder/packages

# Build packages
echo "Building packages..."
cd "${PACKAGES_DIR}"
BUILD_FAILED=0

for pkgdir in */; do
  echo "::group::Building $pkgdir"
  cd "$pkgdir"

  if ! sudo -u builder makepkg --sign --needed --noconfirm -f; then
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
find "${PACKAGES_DIR}" -name "*.pkg.tar.zst.sig" -exec cp {} "${OUTPUT_DIR}/aarch64/" \;

# Create repository database (verify signatures, don't re-sign)
echo "Creating repository database..."
cd "${OUTPUT_DIR}/aarch64"
if [ -n "$(ls *.pkg.tar.zst 2>/dev/null)" ]; then
  repo-add --verify mdrv.db.tar.gz *.pkg.tar.zst
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
