#!/bin/bash
set -euo pipefail

# Configuration
PACKAGER='Umar Alfarouk <medrivia@gmail.com>'
OUTPUT_DIR="/work"
PACKAGES_DIR="/home/builder/packages"
ARCH_DIR="${OUTPUT_DIR}/aarch64"

# Build priority: packages that need to be built first (in dependency order)
# After building each priority package, it will be installed before building dependents
# NOTE: f3d-git should be built manually, not automatically (builds locally without MPI, long compile time)
BUILD_PRIORITY=(
  "ospray"
)

# Get host UID/GID for proper file ownership
HOST_UID="${HOST_UID:-1001}"
HOST_GID="${HOST_GID:-1001}"

echo "Cleaning up any previous builds..."
rm -rf "${ARCH_DIR}"

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

# Upgrade system packages
pacman -Syu --noconfirm

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

# Function to build a single package
build_package() {
  local pkgdir="$1"
  echo "::group::Building $pkgdir"
  cd "$pkgdir"

  # Use PKGDEST environment variable
  if sudo -u builder bash -c "PKGDEST='${ARCH_DIR}' makepkg --needed --syncdeps --noconfirm -f"; then
    # Install the newly built package so dependent packages can find it
    local pkg_file=$(ls "${ARCH_DIR}"/${pkgdir}-*.pkg.tar.* 2>/dev/null | head -1)
    if [ -n "$pkg_file" ]; then
      echo "Installing $pkg_file for dependent packages..."
      pacman -U --noconfirm "$pkg_file" || echo "::warning::Failed to install $pkg_file"
    fi
  else
    echo "::warning::Failed to build $pkgdir"
    BUILD_FAILED=1
    return 1
  fi

  cd ..
  echo "::endgroup::"
  return 0
}

# Function to install a prebuilt package directly
install_prebuilt() {
  local pkgdir="$1"
  local prebuilt
  echo "::group::Installing prebuilt $pkgdir"
  
  # Find any prebuilt package file in this directory
  prebuilt=$(ls "${pkgdir}"/*.pkg.tar.xz "${pkgdir}"/*.pkg.tar.zst 2>/dev/null | head -1)
  
  if [ -n "$prebuilt" ]; then
    echo "Copying prebuilt package: $prebuilt → ${ARCH_DIR}/"
    cp "$prebuilt" "${ARCH_DIR}/"
    
    # Add to repository database so pacman can scan it
    echo "Adding to repository database: $prebuilt"
    cd "${ARCH_DIR}"
    repo-add mdrv.db.tar.gz "$(basename "$prebuilt")"
    cd "${PACKAGES_DIR}"
    
    echo "::endgroup::"
    return 0
  fi
  
  echo "::warning::No prebuilt package found in $pkgdir"
  echo "::endgroup::"
  return 1
}

# Function to build a package with PKGBUILD (or skip if prebuilt exists)
build_or_install() {
  local pkgdir="$1"
  
  # Check for prebuilt package first
  if ls "${pkgdir}"/*.pkg.tar.xz "${pkgdir}"/*.pkg.tar.zst 2>/dev/null | head -1 | grep -q .; then
    install_prebuilt "$pkgdir"
    return $?
  fi
  
  # No prebuilt - build with PKGBUILD
  echo "::group::Building $pkgdir"
  cd "$pkgdir"
  
  # Use PKGDEST environment variable
  if sudo -u builder bash -c "PKGDEST='${ARCH_DIR}' makepkg --needed --syncdeps --noconfirm -f"; then
    # Install newly built package so dependent packages can find it
    local pkg_file=$(ls "${ARCH_DIR}"/${pkgdir}-*.pkg.tar.* 2>/dev/null | head -1)
    if [ -n "$pkg_file" ]; then
      echo "Installing $pkg_file for dependent packages..."
      pacman -U --noconfirm "$pkg_file" || echo "::warning::Failed to install $pkg_file"
    fi
  else
    echo "::warning::Failed to build $pkgdir"
    BUILD_FAILED=1
    return 1
  fi
  
  cd ..
  echo "::endgroup::"
  return 0
}

# Build priority packages first (in specified order)
echo "Building priority packages in dependency order..."
for pkg in "${BUILD_PRIORITY[@]}"; do
  if [ -d "$pkg" ]; then
    # Check for prebuilt package first
    if ls "${pkg}"/*.pkg.tar.xz "${pkg}"/*.pkg.tar.zst 2>/dev/null | head -1 | grep -q .; then
      # Prebuilt package found - install it directly
      install_prebuilt "$pkg"
    else
      # No prebuilt - build with PKGBUILD
      build_or_install "$pkg"
    fi
  else
    echo "::warning::Priority package $pkg not found, skipping..."
  fi
done

# Build remaining packages in alphabetical order
echo "Building remaining packages..."
for pkgdir in */; do
  # Skip packages already built in priority list
  pkgname="${pkgdir%/}"
  if [[ " ${BUILD_PRIORITY[@]} " =~ " ${pkgname} " ]]; then
    echo "Skipping $pkgname (already built as priority package)"
    continue
  fi

  # Check for prebuilt package first
  if ls "${pkgdir}"/*.pkg.tar.xz "${pkgdir}"/*.pkg.tar.zst 2>/dev/null | head -1 | grep -q .; then
    install_prebuilt "$pkgdir"
  else
    build_or_install "$pkgdir"
  fi
done

# Check if packages are in aarch64 directory
echo "Checking ${ARCH_DIR} for packages:"
ls -la "${ARCH_DIR}" || echo "Directory empty or doesn't exist"

# Create repository database (in same directory as packages)
echo "Creating repository database..."
cd "${ARCH_DIR}"
# Build database from all package files (both .pkg.tar.zst and .pkg.tar.xz)
shopt -s nullglob
pkg_files=(*.pkg.tar.zst *.pkg.tar.xz)
if [ ${#pkg_files[@]} -gt 0 ]; then
  repo-add -R mdrv.db.tar.gz "${pkg_files[@]}"
else
  echo "No packages found to build database"
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
