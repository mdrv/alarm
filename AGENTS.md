# Arch Linux ARM Package Repository - Agent Guidelines

This repository hosts custom Arch Linux ARM (aarch64) packages built via GitHub Actions and deployed to GitHub Pages.

## Build Commands

### Local Development (ARM environment required)
```bash
# Build all packages
docker run --rm -v $(pwd):/work -w /work \
  ghcr.io/menci/archlinuxarm:base-devel \
  bash .github/scripts/build-aarch64.sh

# Build single package (requires manual PKGDEST override)
cd packages/<package-name>
makepkg -f --syncdeps
```

### Testing Packages
```bash
# After building, install locally (ARM64 only)
sudo pacman -U aarch64/<package>-<version>-<pkgrel>-aarch64.pkg.tar.zst

# Verify package contents
tar -tzf aarch64/<package>-<version>-<pkgrel>-aarch64.pkg.tar.zst

# Check PKGBUILD syntax
namcap packages/<package>/PKGBUILD
```

### CI/CD Workflow
- **Trigger**: Push to `main`, PRs, manual dispatch, or weekly (Sunday midnight UTC)
- **Runner**: `ubuntu-24.04-arm` with Arch Linux ARM container
- **Output**: Deployed to `gh-pages` branch as GitHub Pages
- **Concurrent builds**: Automatically cancelled

## PKGBUILD Conventions

### File Header
```bash
# Maintainer (aarch64): <your-handle>
# Based on: <original-package> from AUR by <author>
pkgname=<name>
pkgver=<version>  # Use semantic versioning (X.Y.Z)
pkgrel=<1>        # Increment on rebuild without upstream change
pkgdesc="<concise 1-line description>"
arch=('aarch64')
url="<upstream-url>"
license=('MIT')  # Array of licenses
provides=('<pkgname>')
conflicts=('<pkgname>')
```

### Source Array
```bash
source=("<url-to-source>"
        "<additional-files>")
sha256sums=('SKIP'  # For official releases where hash may change
            'abc123...')  # Provide actual hashes for stable URLs
```

### Build Function Pattern
- **Binary packages** (prebuilt): Minimal work, just install
- **Source packages**: Use meson/cmake/make as appropriate
- **Shell completions**: Generate and install in standard locations

### Package Function Pattern
```bash
package() {
  cd "${srcdir}/<extracted-dir>"
  install -Dm755 "<binary>" "${pkgdir}/usr/bin/<name>"
  install -Dm644 "<license>" "${pkgdir}/usr/share/licenses/${pkgname}/LICENSE"
  # Install completions:
  # - zsh: /usr/share/zsh/site-functions/_<name>
  # - bash: /usr/share/bash-completion/completions/<name>
  # - fish: /usr/share/fish/vendor_completions.d/<name>.fish
}
```

## Naming Conventions

### Package Directories
- Located in `packages/<name>/`
- Directory name matches `pkgname` exactly
- Only PKGBUILD and LICENSE files (no source tarballs)
- Use lowercase, hyphen-separated names

### Version Updates
- Update `pkgver` when upstream changes
- Reset `pkgrel=1` when `pkgver` changes
- Increment `pkgrel` only for rebuilds (e.g., dependency changes)
- Follow semantic versioning (X.Y.Z)

## Maintainer Attribution

- Use `# Maintainer (aarch64): <handle>` as first line
- Credit AUR contributors with `# Based on: <pkgname> from AUR by <author>`
- Include email if package contacts are important

## Build Script Guidelines (.github/scripts/build-aarch64.sh)

- **Shell**: Always use `#!/bin/bash` with `set -euo pipefail`
- **Permissions**: Handle UID/GID for container file ownership
- **Sandbox**: Disable pacman sandbox (`DisableSandbox` in pacman.conf)
- **User management**: Create builder user matching host UID/GID
- **Build loop**: Iterate over `packages/*/` directories
- **Error handling**: Track build failures, exit with code 1 on any failure
- **Repo database**: Always create `mdrv.db.tar.gz` using `repo-add -R`

## GitHub Actions Conventions

- Use `ghcr.io/menci/archlinuxarm:base-devel` for ARM64 builds
- Set concurrency group to `aarch64-repo`
- Deploy to `gh-pages` branch only from `main`
- Upload build artifacts with 7-day retention
- Use `web-indexer` for HTML index generation (nord theme)

## Repository Structure

```
/x/g/alarm/
├── .github/
│   ├── workflows/build.yml    # CI/CD pipeline
│   └── scripts/build-aarch64.sh  # Main build script
├── packages/
│   ├── <name>/               # Package directory
│   │   ├── PKGBUILD          # Package definition
│   │   └── LICENSE           # License file
├── aarch64/                  # Generated build output (not committed)
└── README.md                 # User documentation
```

## Error Handling

- **Build failures**: GitHub Actions will exit with error, workflow fails
- **Missing packages**: Build script warns but continues
- **Permission issues**: Handled via UID/GID mapping in container
- **Database creation**: Fails gracefully if no packages built

## Dependencies

- **Prebuilt binary packages**: Source from official releases (GitHub, etc.)
- **Source builds**: Declare `depends=()` and `makedepends=()` arrays
- **Check Arch Linux ARM official repo** for existing dependencies first

## Testing Checklist

Before committing changes:
- [ ] PKGBUILD syntax is valid (use `namcap`)
- [ ] Package description is concise and accurate
- [ ] License file is included and correct
- [ ] Source URLs are correct and accessible
- [ ] sha256sums are accurate (or 'SKIP' for volatile URLs)
- [ ] Shell completions are installed in standard locations
- [ ] README.md is updated if new package added

## Deployment

- **Automated**: Push to `main` branch triggers build
- **Manual**: Use GitHub Actions "workflow_dispatch"
- **Scheduled**: Weekly Sunday midnight UTC rebuilds
- **URL**: `https://mdrv.github.io/alarm/aarch64`

## Package Signing

- Packages are **unsigned** - users must add `SigLevel = Optional TrustAll` to `/etc/pacman.conf`
- No GPG signing process implemented (optional future enhancement)

## Adding New Packages

1. Create `packages/<name>/` directory
2. Write PKGBUILD following conventions above
3. Add LICENSE file if required
4. Test locally in ARM container
5. Commit and push to trigger CI/CD
6. Update README.md with package description

**Important - Large/Complex Source Builds:**
- For packages with long build times (e.g., requiring source compilation with many dependencies like f3d-git, mpich), do NOT add to BUILD_PRIORITY in `.github/scripts/build-aarch64.sh`
- Instead, document in README that these should be built manually: `Build locally with: cd packages/<name> && makepkg -si`
- CI/CD should complete in ~5-8 minutes (ospray + other small packages)
- Adding large source builds to auto-build makes CI/CD take 20+ minutes and blocks other packages


**Note on f3d Package:**
- f3d-git (source build with many deps) removed from auto-build
- Added f3d (prebuilt aarch64 AppImage from v3.4.1 release)
- Prebuilt version uses stable release v3.4.1 instead of dev branch
- Installs to /opt/f3d/ as AppImage

