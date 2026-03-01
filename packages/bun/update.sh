#!/bin/bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PKGBUILD="${SCRIPT_DIR}/PKGBUILD"

echo "Fetching latest Bun version from GitHub API..."
LATEST_RELEASE=$(curl -s "https://api.github.com/repos/oven-sh/bun/releases/latest")
LATEST_VERSION=$(echo "$LATEST_RELEASE" | grep -oP '"tag_name":\s*"bun-v\K[^"]+')
LATEST_URL="https://github.com/oven-sh/bun/releases/download/bun-v${LATEST_VERSION}/bun-linux-aarch64.zip"

if [[ -z "$LATEST_VERSION" ]]; then
  echo "Error: Could not determine latest version"
  exit 1
fi

CURRENT_VERSION=$(grep "^pkgver=" "$PKGBUILD" | cut -d= -f2)

echo "Current version: $CURRENT_VERSION"
echo "Latest version:  $LATEST_VERSION"

if [[ "$LATEST_VERSION" == "$CURRENT_VERSION" ]]; then
  echo "Already up to date!"
  exit 0
fi

echo "Downloading ${LATEST_URL##*/}..."
cd "$SCRIPT_DIR"
curl -fsSL -o "bun-aarch64-${LATEST_VERSION}.zip" "$LATEST_URL"

echo "Computing sha256sum..."
SHA256SUM=$(sha256sum "bun-aarch64-${LATEST_VERSION}.zip" | cut -d' ' -f1)

echo "Updating PKGBUILD..."
sed -i "s/^pkgver=.*/pkgver=${LATEST_VERSION}/" "$PKGBUILD"
sed -i "s/^pkgrel=.*/pkgrel=1/" "$PKGBUILD"
sed -i "s|^source=(\"bun-aarch64-.*|source=(\"bun-aarch64-\${pkgver}.zip::https://github.com/oven-sh/bun/releases/download/bun-v\${pkgver}/bun-linux-aarch64.zip\"|" "$PKGBUILD"
sed -i "0,/SKIP/s|SKIP|${SHA256SUM}|" "$PKGBUILD"

echo "Cleaning up downloaded file..."
rm -f "bun-aarch64-${LATEST_VERSION}.zip"

echo "✓ Updated to version ${LATEST_VERSION}"
echo "  - pkgver: ${LATEST_VERSION}"
echo "  - pkgrel: 1"
echo "  - sha256sum: ${SHA256SUM}"
echo "  - LICENSE sha256sum: SKIP (local file)"
echo ""
echo "Review the changes, then commit and push to trigger CI/CD build."