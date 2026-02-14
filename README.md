# Arch Linux ARM (aarch64) Repository

Personal Arch Linux ARM (aarch64) package repository built on GitHub Actions.

## Usage

Add to `/etc/pacman.conf`:

```ini
[mdrv]
SigLevel = Required DatabaseOptional
LocalFileSigLevel = Optional
Server = https://mdrv.github.io/alarm/aarch64
```

**Important:** The repository packages are signed by the official Arch Linux ARM Build System key (68B3537F39A313B3E574D06777193F152BDBE6A6).

Then update and install:

```bash
sudo pacman -Syu
sudo pacman -S mdrv/bun
sudo pacman -S mdrv/pocketbase-bin
sudo pacman -S mdrv/tofi
```

## Available Packages

- **bun** - Fast JavaScript runtime, bundler, test runner, and package manager
- **pocketbase-bin** - Open source backend for your next project in 1 file
- **tofi** - Tiny rofi / dmenu replacement for wlroots-based Wayland compositors

## Package Signing

All packages are signed using the official Arch Linux ARM Build System key:

```
Key ID: 68B3537F39A313B3E574D06777193F152BDBE6A6
Owner: Arch Linux ARM Build System
```

To verify package signatures, ensure the Arch Linux ARM keyring is installed:

```bash
sudo pacman -S archlinuxarm-keyring
```

## Building

Packages are automatically built on GitHub Actions using QEMU emulation on Ubuntu runners.

## License

Each package follows its own license. See individual package sources for details.
