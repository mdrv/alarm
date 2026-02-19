# Arch Linux ARM (aarch64) Repository

Personal Arch Linux ARM (aarch64) package repository built on GitHub Actions.

## Usage

Add to `/etc/pacman.conf`:

```ini
[mdrv]
SigLevel = Optional TrustAll
Server = https://mdrv.github.io/alarm/aarch64
```

Then update and install:

```bash
sudo pacman -Syu
sudo pacman -S mdrv/bun
sudo pacman -S mdrv/tofi
```

## Package Signing

Packages are **unsigned**. Add `SigLevel = Optional TrustAll` in `/etc/pacman.conf`.

## Available Packages

- **bun** - Fast JavaScript runtime, bundler, test runner, and package manager (prebuilt binary from official releases)
- **f3d** - Fast and minimalist 3D viewer with ray tracing support (prebuilt aarch64 binary)
- **ospray** - Ray Tracing Based Rendering Engine for High-Fidelity Visualization (prebuilt aarch64 binary from official releases)
- **tofi** - Tiny rofi / dmenu replacement for wlroots-based Wayland compositors

## Building

Packages are automatically built on GitHub Actions using native ARM64 runners (ubuntu-24.04-arm).

## License

Each package follows its own license. See individual package sources for details.
