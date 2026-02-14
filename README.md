# Arch Linux ARM (aarch64) Repository

Personal Arch Linux ARM (aarch64) package repository built on GitHub Actions.

## Usage

Add to `/etc/pacman.conf`:

```ini
[alarm]
SigLevel = Optional
Server = https://mdrv.github.io/alarm/aarch64
```

Then update and install:

```bash
sudo pacman -Syu
sudo pacman -S alarm/bun
sudo pacman -S alarm/pocketbase-bin
```

## Available Packages

- **bun** - Fast JavaScript runtime, bundler, test runner, and package manager
- **pocketbase-bin** - Open source backend for your next project in 1 file

## Building

Packages are automatically built on GitHub Actions using native ARM64 runners.

## License

Each package follows its own license. See individual package sources for details.
