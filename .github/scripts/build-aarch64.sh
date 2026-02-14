#!/bin/bash
set -euo pipefail

# Configuration
PACKAGER='mdrv <mdrv@users.noreply.github.com>'
OUTPUT_DIR="/work"
PACKAGES_DIR="/home/builder/packages"
ARCH_DIR="${OUTPUT_DIR}/aarch64"

# Get host UID/GID for proper file ownership
HOST_UID="${HOST_UID:-1001}"
HOST_GID="${HOST_GID:-1001}"

echo "Host UID: ${HOST_UID}, Host GID: ${HOST_GID}"

# Disable pacman sandbox (Landlock not supported in container)
echo "Configuring pacman..."
sed -i 's|^#\?DisableSandbox.*|DisableSandbox|' /etc/pacman.conf || echo "DisableSandbox" >> /etc/pacman.conf

# Create builder user with same UID as host to avoid permission issues
echo "Setting up builder user..."
useradd -m -u "${HOST_UID}" builder 2>/dev/null || true

# Configure sudo: allow builder to run pacman without password
echo "Allowing builder to run pacman without password..."
echo "builder ALL=(ALL) NOPASSWD: /usr/bin/pacman" > /etc/sudoers.d/builder
chmod 440 /etc/sudoers.d/builder

# Import official Arch Linux ARM keyring
echo "Importing Arch Linux ARM keyring..."
pacman-key --init
pacman-key --populate archlinuxarm

# Initialize pacman and install build dependencies
echo "Initializing pacman and installing dependencies..."
pacman -Syu --noconfirm
pacman -S --noconfirm --needed meson scdoc wayland-protocols

# Configure makepkg
echo "PACKAGER=\"${PACKAGER}\"" >> /etc/makepkg.conf

# Prepare directories
echo "Preparing directories..."
mkdir -p "${ARCH_DIR}"
chown -R builder:builder "${OUTPUT_DIR}"
cp -r "${OUTPUT_DIR}/packages" /home/builder/
chown -R builder:builder /home/builder/packages

# Build packages
echo "Building packages..."
cd "${PACKAGES_DIR}"
BUILD_FAILED=0

for pkgdir in */; do
  echo "::group::Building $pkgdir"
  cd "$pkgdir"

  # Use PKGDEST environment variable
  if ! sudo -u builder bash -c "PKGDEST='${ARCH_DIR}' makepkg --needed --syncdeps --noconfirm -f"; then
    echo "::warning::Failed to build $pkgdir"
    BUILD_FAILED=1
  fi

  cd ..
  echo "::endgroup::"
done

# Check if packages are in aarch64 directory
echo "Checking ${ARCH_DIR} for packages:"
ls -la "${ARCH_DIR}" || echo "Directory empty or doesn't exist"

# Create repository database (in same directory as packages)
echo "Creating repository database..."
cd "${ARCH_DIR}"
# Build database from all package files (both .pkg.tar.zst and .pkg.tar.xz)
if compgen -G "*.pkg.tar.zst" >/dev/null; then
  repo-add -R mdrv.db.tar.gz ./*.pkg.tar.zst
elif compgen -G "*.pkg.tar.xz" >/dev/null; then
  repo-add -R mdrv.db.tar.gz ./*.pkg.tar.xz
else
  echo "No packages found to build database"
fi

# Generate index for aarch64/ directory
echo "Generating index.html for aarch64/..."
cd "${ARCH_DIR}"

{
  echo "<html><head><title>Index of /aarch64</title></head><body><pre>"
  echo "<a href=\"../\">../</a>"
  for f in *.pkg.tar.zst *.pkg.tar.xz *.db.tar.gz *.files.tar.gz *.db *.files; do
    [ -e "$f" ] || continue
    printf '%-60s\n' "$f" >> index.html
  done
  echo "</pre></body></html>"
} > index.html 2>/dev/null

# Generate root index.html
echo "Generating root index.html..."
cd "${OUTPUT_DIR}"

{
  echo "<html><head><title>Index of /</title></head><body><pre>"
  echo "<a href=\"aarch64/\">aarch64/</a>"
  echo "</pre></body></html>"
} > index.html 2>/dev/null

# Fix permissions - chown to host user so files are accessible outside container
echo "Fixing permissions to host user ${HOST_UID}:${HOST_GID}..."
chown -R "${HOST_UID}:${HOST_GID}" "${OUTPUT_DIR}/aarch64" "${OUTPUT_DIR}/index.html"

# Exit with error if any build failed
if [ "$BUILD_FAILED" -eq 1 ]; then
  echo "::error::One or more packages failed to build"
  exit 1
fi

echo "Build complete!"
