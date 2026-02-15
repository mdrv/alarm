#!/bin/bash
set -euo pipefail

# Configuration
PACKAGER='Umar Alfarouk <medrivia@gmail.com>'
OUTPUT_DIR="/work"
PACKAGES_DIR="/home/builder/packages"
ARCH_DIR="${OUTPUT_DIR}/aarch64"

# Get host UID/GID for proper file ownership
HOST_UID="${HOST_UID:-1001}"
HOST_GID="${HOST_GID:-1001}"

echo "Cleaning up any previous builds..."
rm -rf "${ARCH_DIR}"


echo "Host UID: ${HOST_UID}, Host GID: ${HOST_GID}"

# Setup GPG signing if GPG_PRIVATE_KEY is provided
if [ -n "${GPG_PRIVATE_KEY:-}" ]; then
  echo "Setting up GPG signing..."

  # Create builder's .gnupg directory with proper ownership
  mkdir -p /home/builder/.gnupg
  chown builder:builder /home/builder/.gnupg
  chmod 700 /home/builder/.gnupg

  # Import GPG private key as root
  echo "${GPG_PRIVATE_KEY}" | gpg --batch --import --homedir /root/.gnupg

  # Copy keyring to builder user with correct ownership
  cp -r /root/.gnupg/* /home/builder/.gnupg/
  chown -R builder:builder /home/builder/.gnupg
  chmod 700 /home/builder/.gnupg
  find /home/builder/.gnupg -type d -exec chmod 700 {} \;
  find /home/builder/.gnupg -type f -exec chmod 600 {} \;

  # Use direct key ID (16 chars from known fingerprint)
  KEY_ID="8F6852C610B71619"

  echo "Using GPG key ID: ${KEY_ID}"

  # Verify secret key exists
  if ! su - builder -c "gpg --batch --list-secret-keys --keyid-format=long '${KEY_ID}'" >/dev/null 2>&1; then
    echo "::error::GPG key ${KEY_ID} not found in builder's keyring after import"
    exit 1
  fi

  # Configure GPG for non-interactive signing (in builder's homedir)
  su - builder -c "echo 'default-key ${KEY_ID}' > /home/builder/.gnupg/gpg.conf"
  su - builder -c "echo 'pinentry-mode loopback' >> /home/builder/.gnupg/gpg.conf"

  # Add signing configuration to makepkg.conf
  echo "GPGKEY=\"${KEY_ID}\"" >> /etc/makepkg.conf

  # Set up passphrase for non-interactive use
  if [ -n "${GPG_PASSPHRASE:-}" ]; then
    echo "${GPG_PASSPHRASE}" > /tmp/gpg-passphrase
    chmod 600 /tmp/gpg-passphrase
    export GPG_TTY=/dev/null
  fi
else
  echo "::error::GPG_PRIVATE_KEY not set. Please add it to repository secrets."
  exit 1
fi


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

# Install only build dependencies (no full system upgrade)
echo "Installing build dependencies only..."
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
  # Add --sign flag if GPG is configured
  if [ -n "${KEY_ID:-}" ]; then
    if ! sudo -u builder bash -c "PKGDEST='${ARCH_DIR}' makepkg --needed --syncdeps --noconfirm -f --sign"; then
      echo "::warning::Failed to build $pkgdir"
      BUILD_FAILED=1
    fi
  else
    if ! sudo -u builder bash -c "PKGDEST='${ARCH_DIR}' makepkg --needed --syncdeps --noconfirm -f"; then
      echo "::warning::Failed to build $pkgdir"
      BUILD_FAILED=1
    fi
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
# Add --sign flag if GPG is configured
if [ -n "${KEY_ID:-}" ]; then
  if compgen -G "*.pkg.tar.zst" >/dev/null; then
    repo-add -R -s -k "${KEY_ID}" mdrv.db.tar.gz ./*.pkg.tar.zst
  elif compgen -G "*.pkg.tar.xz" >/dev/null; then
    repo-add -R -s -k "${KEY_ID}" mdrv.db.tar.gz ./*.pkg.tar.xz
  else
    echo "No packages found to build database"
  fi
else
  if compgen -G "*.pkg.tar.zst" >/dev/null; then
    repo-add -R mdrv.db.tar.gz ./*.pkg.tar.zst
  elif compgen -G "*.pkg.tar.xz" >/dev/null; then
    repo-add -R mdrv.db.tar.gz ./*.pkg.tar.xz
  else
    echo "No packages found to build database"
  fi
fi

# Cleanup: remove GPG passphrase file if it was created
if [ -f /tmp/gpg-passphrase ]; then
  shred -u /tmp/gpg-passphrase
fi

# Fix permissions - chown to host user so files are accessible outside container
echo "Fixing permissions to host user ${HOST_UID}:${HOST_GID}..."
chown -R "${HOST_UID}:${HOST_GID}" "${OUTPUT_DIR}/aarch64"

# Exit with error if any build failed
if [ "$BUILD_FAILED" -eq 1 ]; then
  echo "::error::One or more packages failed to build"
  exit 1
fi

echo "Build complete!"
