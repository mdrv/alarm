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

# Configure makepkg - create user-local config for PKGDEST
echo "Configuring makepkg for builder..."
echo "PACKAGER=\"${PACKAGER}\"" >> /etc/makepkg.conf
sudo -u builder bash -c "echo 'PKGDEST=\"${OUTPUT_DIR}/aarch64\"' > /home/builder/.makepkg.conf"

# Prepare packages directory
echo "Preparing packages directory..."
mkdir -p "${OUTPUT_DIR}/aarch64"
chown -R builder:builder "${OUTPUT_DIR}/aarch64"
cp -r "${OUTPUT_DIR}/packages" /home/builder/
chown -R builder:builder /home/builder/packages

# Build packages (unsigned, PKGDEST set in user-local config)
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

# Generate index.html with file listing
echo "Generating index.html..."
BUILD_DATE=$(date -u +"%Y-%m-%d %H:%M:%S UTC")
cd "${OUTPUT_DIR}/aarch64"

cat > index.html <<EOF
<html><head><title>Index of /aarch64</title></head>
<body>
<h1>Index of /aarch64</h1>
<hr><pre><a href="../">../</a>
EOF

# List all files with size and date
for file in *.pkg.tar.zst *.db.tar.gz *.files.tar.gz; do
  if [ -f "$file" ]; then
    SIZE=$(stat -c%s "$file" 2>/dev/null || echo 0)
    DATE=$(stat -c%y-%b-%d %H:%M "$file" 2>/dev/null || echo "unknown")
    # Format: pad filename to 60 chars, then date and size
    printf '%-60s  %-20s  %15s\n' "$file" "$DATE" "$SIZE" >> index.html
  fi
done

echo "</pre></body></html>" >> index.html

# Create repository database (unsigned)
echo "Creating repository database..."
if [ -n "$(ls *.pkg.tar.zst 2>/dev/null)" ]; then
  repo-add mdrv.db.tar.gz *.pkg.tar.zst
else
  echo "No packages built, creating empty database files"
  touch mdrv.db.tar.gz
  touch mdrv.files.tar.gz
fi

# Fix permissions
echo "Fixing permissions..."
chown -R $(id -u):$(id -g) "${OUTPUT_DIR}/aarch64"

# Exit with error if any build failed
if [ "$BUILD_FAILED" -eq 1 ]; then
  echo "::error::One or more packages failed to build"
  exit 1
fi

echo "Build complete!"
