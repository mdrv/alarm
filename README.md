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
sudo pacman -S mdrv/pocketbase-bin
sudo pacman -S mdrv/tofi
```

## Available Packages

- **bun** - Fast JavaScript runtime, bundler, test runner, and package manager (prebuilt binary from official releases)
- **pocketbase-bin** - Open source backend for your next project in 1 file
- **tofi** - Tiny rofi / dmenu replacement for wlroots-based Wayland compositors

## Package Signing

Packages are **unsigned** for simplicity. This is standard practice for personal repositories.

Set `SigLevel = Optional TrustAll` in `/etc/pacman.conf` to disable signature verification.

## Building

Packages are automatically built on GitHub Actions using QEMU emulation on Ubuntu runners.

## License

Each package follows its own license. See individual package sources for details.
