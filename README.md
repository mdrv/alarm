# Arch Linux Package Repository

Personal Arch Linux package repository built on GitHub Actions.

## Usage

### aarch64 (Arch Linux ARM)

Add to `/etc/pacman.conf`:

```ini
[mdrv]
SigLevel = Optional TrustAll
Server = https://mdrv.github.io/alarm/aarch64
```

### x86_64

Only **surrealdb** is available for x86_64 (other packages are already in official repositories).

```ini
[mdrv]
SigLevel = Optional TrustAll
Server = https://mdrv.github.io/alarm/x86_64
```

Then update and install:

```bash
sudo pacman -Syu
```

## Available Packages

### aarch64

- **bun** - Fast JavaScript runtime, bundler, test runner, and package manager (prebuilt binary from official releases)
- **f3d** - Fast and minimalist 3D viewer with ray tracing support (prebuilt aarch64 binary)
- **ospray** - Ray Tracing Based Rendering Engine for High-Fidelity Visualization (prebuilt aarch64 binary from official releases)
- **runit** - UNIX init scheme with service supervision
- **surrealdb** - Scalable, distributed, collaborative document-graph database
- **tofi** - Tiny rofi / dmenu replacement for wlroots-based Wayland compositors

### x86_64

- **surrealdb** - Scalable, distributed, collaborative document-graph database

## Package Signing

Packages are **unsigned**. Add `SigLevel = Optional TrustAll` in `/etc/pacman.conf`.

## Building

Packages are automatically built on GitHub Actions:

- **aarch64**: native ARM runners (`ubuntu-24.04-arm`) with `archlinuxarm:base-devel`
- **x86_64**: standard runners (`ubuntu-latest`) with `archlinux:base-devel`

## License

Each package follows its own license. See individual package sources for details.
