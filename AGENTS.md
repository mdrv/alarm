# Arch Linux Package Repository - Agent Guidelines

This repository hosts custom Arch Linux packages (aarch64 and x86_64) built via GitHub Actions and deployed to GitHub Pages.

## Architecture

- **aarch64**: All packages — built on `ubuntu-24.04-arm` runner with `archlinuxarm:base-devel` container
- **x86_64**: Select packages only (e.g. surrealdb) — built on `ubuntu-latest` runner with `archlinux:base-devel` container
- Most packages are aarch64-only since they already exist in official x86_64 repos

## Build Commands

### Local Development

```bash
# Build aarch64 packages
docker run --rm -v $(pwd):/work -w /work \
  -e TARGET_ARCH=aarch64 \
  ghcr.io/menci/archlinuxarm:base-devel \
  -c "pacman -Syu --noconfirm nushell && nu /work/.github/scripts/build.nu"

# Build x86_64 packages
docker run --rm -v $(pwd):/work -w /work \
  -e TARGET_ARCH=x86_64 \
  archlinux:base-devel \
  -c "pacman -Syu --noconfirm nushell && nu /work/.github/scripts/build.nu"

# Build single package (requires manual PKGDEST override)
cd packages/<package-name>
makepkg -f --syncdeps
```

### Testing Packages

```bash
# After building, install locally
sudo pacman -U aarch64/<package>-<version>-<pkgrel>-aarch64.pkg.tar.zst
sudo pacman -U x86_64/<package>-<version>-<pkgrel>-x86_64.pkg.tar.zst

# Verify package contents
tar -tzf aarch64/<package>-<version>-<pkgrel>-aarch64.pkg.tar.zst

# Check PKGBUILD syntax
namcap packages/<package>/PKGBUILD
```

### CI/CD Workflow

- **Trigger**: Push to `main`, PRs, manual dispatch, or after update workflow
- **Jobs**: `build-aarch64` + `build-x86_64` (parallel) → `deploy`
- **Output**: Deployed to `gh-pages` branch as GitHub Pages
- **Concurrent builds**: Automatically cancelled

## PKGBUILD Conventions

### File Header

```bash
# Maintainer (aarch64): <your-handle>
# Based on: <original-package> from AUR by <author>
pkgname=<name>
pkgver=<version>  # Use semantic versioning (X.Y.Z)
pkgrel=1          # Increment on rebuild without upstream change
pkgdesc="<concise 1-line description>"
arch=('x86_64' 'aarch64')  # Always declare both even if building for one
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

## Package Configuration (update.jsonc)

Each package entry in `update.jsonc` controls how it's built:

```jsonc
{
	"pkgname": "example",
	"repo": "https://github.com/owner/repo", // GitHub repo (for auto-updates)
	"path": "packages/example", // Path to PKGBUILD directory
	"arch": ["aarch64"], // Array: ["aarch64"], ["x86_64"], or both
	"build": true, // true = makepkg, false = copy from prebuilt/
	"priority": 10 // Lower = built first
}
```

### Architecture Field

- `["aarch64"]` — only built in the aarch64 job
- `["x86_64"]` — only built in the x86_64 job
- `["aarch64", "x86_64"]` — built in both jobs

## Build Script Guidelines (.github/scripts/build.nu)

- **Language**: Nushell (`.nu`)
- **Architecture**: Controlled via `TARGET_ARCH` environment variable (`aarch64` or `x86_64`)
- **Keyring**: Imports `archlinuxarm` keyring for aarch64, `archlinux` for x86_64
- **Permissions**: Handle UID/GID for container file ownership
- **Sandbox**: Disable pacman sandbox (`DisableSandbox` in pacman.conf)
- **User management**: Create builder user matching host UID/GID
- **Package filtering**: Reads `arch` field from `update.jsonc`, only builds matching packages
- **Error handling**: Track build failures, exit with code 1 on any failure
- **Repo database**: Always create `mdrv.db.tar.gz` using `repo-add -R`

## GitHub Actions Conventions

- **aarch64 job**: `ubuntu-24.04-arm` runner + `ghcr.io/menci/archlinuxarm:base-devel` container
- **x86_64 job**: `ubuntu-latest` runner + `archlinux:base-devel` container
- Set concurrency group to `arch-repo`
- Deploy job downloads artifacts from both build jobs, merges into `public/`
- Deploy to `gh-pages` branch only from `main`
- Upload build artifacts with 7-day retention
- Use `web-indexer` for HTML index generation (nord theme)

## Repository Structure

```
/x/g/alarm/
├── .github/
│   ├── workflows/build.yml           # CI/CD pipeline (dual-arch)
│   └── scripts/build.nu              # Main build script (Nushell, arch-aware)
├── packages/
│   ├── <name>/                       # Package directory
│   │   ├── PKGBUILD                  # Package definition
│   │   └── LICENSE                   # License file
├── prebuilt/                          # Pre-built .pkg.tar.xz files (aarch64 only)
├── aarch64/                           # Generated aarch64 build output (not committed)
├── x86_64/                            # Generated x86_64 build output (not committed)
├── update.jsonc                       # Package registry (arch flags, build config)
└── README.md                          # User documentation
```

## Error Handling

- **Build failures**: GitHub Actions will exit with error, workflow fails
- **Missing packages**: Build script warns but continues
- **Permission issues**: Handled via UID/GID mapping in container
- **Database creation**: Fails gracefully if no packages built

## Dependencies

- **Prebuilt binary packages**: Source from official releases (GitHub, etc.)
- **Source builds**: Declare `depends=()` and `makedepends=()` arrays
- **Check Arch Linux ARM official repo** for existing dependencies first (for aarch64)
- **Check official Arch repos** for existing dependencies (for x86_64)

## Testing Checklist

Before committing changes:

- [ ] PKGBUILD syntax is valid (use `namcap`)
- [ ] Package description is concise and accurate
- [ ] License file is included and correct
- [ ] Source URLs are correct and accessible
- [ ] sha256sums are accurate (or 'SKIP' for volatile URLs)
- [ ] Shell completions are installed in standard locations
- [ ] README.md is updated if new package added
- [ ] `update.jsonc` entry is added/updated with correct `arch` array

## Deployment

- **Automated**: Push to `main` branch triggers build
- **Manual**: Use GitHub Actions "workflow_dispatch"
- **URLs**:
  - aarch64: `https://mdrv.github.io/alarm/aarch64`
  - x86_64: `https://mdrv.github.io/alarm/x86_64`

## Package Signing

- Packages are **unsigned** — users must add `SigLevel = Optional TrustAll` to `/etc/pacman.conf`
- No GPG signing process implemented (optional future enhancement)

## Adding New Packages

1. Create `packages/<name>/` directory
2. Write PKGBUILD following conventions above (always declare both arches)
3. Add LICENSE file if required
4. Add entry to `update.jsonc` with appropriate `arch` array
5. Test locally in appropriate container (ARM for aarch64, archlinux for x86_64)
6. Commit and push to trigger CI/CD
7. Update README.md with package description

**Important - Large/Complex Source Builds:**

- For packages with long build times (e.g., requiring source compilation with many dependencies like f3d-git, mpich), do NOT add to auto-build
- Instead, document in README that these should be built manually: `Build locally with: cd packages/<name> && makepkg -si`
- CI/CD should complete in ~5-8 minutes per architecture
- Adding large source builds to auto-build makes CI/CD take 20+ minutes and blocks other packages

**Note on f3d Package:**

- f3d-git (source build with many deps) removed from auto-build
- Added f3d (prebuilt aarch64 AppImage from v3.4.1 release)
- Prebuilt version uses stable release v3.4.1 instead of dev branch
- Installs to /opt/f3d/ as AppImage
