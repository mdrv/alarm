# Arch Linux ARM (aarch64) Package Repository - Work in Progress

## Status: ⚠️ INCOMPLETE - Build workflow failing

This repository is being developed to host personal Arch Linux ARM (aarch64) packages on GitHub Pages.

## What's Working

### Repository Structure
```
/
├── packages/
│   ├── bun/PKGBUILD (binary PKGBUILD - simpler than source)
│   ├── pocketbase-bin/PKGBUILD
│   └── tofi/PKGBUILD
├── .github/
│   └── workflows/build.yml
├── index.html.template
└── README.md
```

### GitHub Actions Workflow
- Triggers on push to main, PRs, or manual dispatch
- Uses QEMU emulation (`ubuntu-latest` with `ghcr.io/menci/archlinuxarm:base-devel`)
- Builds packages in container with non-root user
- Deploys `public/aarch64/` to `gh-pages` branch
- Has concurrency protection

## Issues Encountered

### 1. **GPG Signing Problems**
- **Problem**: Using official Arch Linux ARM Build System key (68B3537F39A313B3E574D06777193F152BDBE6A6) in ephemeral CI container
- **Symptoms**:
  - `==> WARNING: Failed to sign package file`
  - Multiple GPG warnings about weak key signatures
  - Revocation certificate errors
- **Tried Solutions**:
  - Import key via `pacman-key --populate archlinuxarm`
  - Set `GPGKEY` in environment and `/etc/makepkg.conf`
  - Allow weak signatures with `--allow-weak-key-signatures`
- **Current Status**: All packages fail to sign, causing build failures

### 2. **Pacman Database Sync**
- **Problem**: `makepkg` runs as non-root user (builder) but pacman databases aren't synchronized
- **Symptoms**:
  - `warning: database file for 'core' does not exist`
  - `warning: database file for 'extra' does not exist`
  - `==> ERROR: Could not resolve all dependencies`
- **Tried Solutions**:
  - Run `pacman -Syu --noconfirm` before building (for root user)
  - Run `pacman -Syu` inside `su builder -lc` block (for builder user)
- **Current Status**: Both approaches failed with "cannot perform this operation unless you are root"

### 3. **Container Environment Issues**
- **Problem**: QEMU emulation with `ubuntu-latest` + `ghcr.io/menci/archlinuxarm:base-devel`
- **Symptoms**:
  - Slow build times (5+ minutes for simple packages)
  - `landlock` warnings in older kernel
  - Pacman database files missing
- **Tried Solutions**:
  - Disable `landlock` via `BUILDENV=!landlock` and `/etc/makepkg.conf`
  - Install build dependencies (`meson`, `scdoc`, `wayland-protocols`)
  - Use different container approach

### 4. **Package Build Issues**
- **bun**: Compiling from source (WebKit + Zig) - extremely slow and complex
- **tofi**: Missing buildtime dependencies despite being in `makedepends`
- **pocketbase-bin**: Binary package, should work but failing to sign
- **Symptoms**: All three packages fail to build successfully

## What We've Learned

### For PKGBUILD Design

1. **Binary PKGBUILDs Are Better for CI**:
   - `bun-bin` (download official prebuilt binary) is MUCH simpler than compiling from source
   - Less error-prone
   - Faster build times
   - No complex toolchain requirements

2. **GPG Signing in Ephemeral CI Is Problematic**:
   - Official keys don't work well in short-lived containers
   - Consider generating a dedicated repo signing key for personal use
   - Or skip signing entirely and use `SigLevel = Optional TrustAll`

3. **Pacman Must Be Initialized Per-User**:
   - `pacman -Syu` must run INSIDE the same shell as `makepkg`
   - Running it as root beforehand doesn't help the builder user
   - Use `sudo -u builder bash -lc 'pacman -Syu'` wrapper

4. **QEMU Emulation Has Overhead**:
   - Native ARM runners (`ubuntu-24.04-arm`) are faster and more reliable
   - Consider switching if available for your repository

5. **Don't Over-Engineer**:
   - The Arch Linux ARM base image works for most users
   - Don't try to work around every limitation manually

## Next Steps (NOT YET IMPLEMENTED)

### High-Priority Fixes Needed

1. **Fix GPG Signing**:
   - Generate a new GPG key pair for this repository
   - Add `GPG_PRIVATE_KEY` to GitHub Secrets
   - Import key in workflow and sign with loopback mode
   - **OR**: Skip signing and document that packages are unsigned

2. **Fix Package Builds**:
   - Switch `bun` to `bun-bin` binary PKGBUILD (simplest)
   - Keep `pocketbase-bin` and `tofi` as-is (they should work)
   - Debug why all three packages are failing

3. **Consider Container Strategy**:
   - Try switching to `ubuntu-24.04-arm` runners (native ARM, no QEMU)
   - OR use a more minimal container image
   - OR ask Arch Linux ARM community about working container images for CI

4. **Test Locally**:
   - Try running the build script locally with QEMU/Docker
   - Verify PKGBUILDs work correctly
   - Test package installation

## Current Package List

1. **bun** - Fast JavaScript runtime (compiling from source - PROBLEMATIC)
2. **pocketbase-bin** - Binary backend package (should work)
3. **tofi** - Wayland launcher (missing buildtime deps - PROBLEMATIC)

## Documentation References

- Arch Linux ARM: https://archlinuxarm.org/
- Arch Packaging: https://wiki.archlinux.org/title/Arch_Packaging_Standards
- GPG in CI: https://wiki.archlinux.org/title/Makepkg#Package_signing

---

**Last Updated**: 2026-02-14
**Status**: Workflow debugging in progress
