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

### Package Signing (Optional)

Packages are signed with GPG. To enable signature verification, import the repository key:

```bash
wget https://mdrv.github.io/alarm/aarch64/mdrv-key.asc
sudo pacman-key --add mdrv-key.asc
sudo pacman-key --lsign-key <KEY_ID>
```

Then update `/etc/pacman.conf`:

```ini
[mdrv]
SigLevel = Required Trusted
Server = https://mdrv.github.io/alarm/aarch64
```

If signing fails during build, packages will be deployed as unsigned and you should use `SigLevel = Optional TrustAll`.

## Available Packages

- **bun** - Fast JavaScript runtime, bundler, test runner, and package manager (prebuilt binary from official releases)
- **tofi** - Tiny rofi / dmenu replacement for wlroots-based Wayland compositors

## Building

Packages are automatically built on GitHub Actions using native ARM64 runners (ubuntu-24.04-arm).

## License

Each package follows its own license. See individual package sources for details.
