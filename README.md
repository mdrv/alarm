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

Several packages are also available for x86_64 (see list below).

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
- **mdrv-oc** - OpenCode session database manager (list, move, export/import, inspect sessions)
- **ospray** - Ray Tracing Based Rendering Engine for High-Fidelity Visualization (prebuilt aarch64 binary from official releases)
- **opencode** - AI coding agent for the terminal
- **runit** - UNIX init scheme with service supervision
- **surrealdb** - Scalable, distributed, collaborative document-graph database
- **tofi** - Tiny rofi / dmenu replacement for wlroots-based Wayland compositors
- **turso** - In-process SQL database engine compatible with SQLite

### x86_64

- **bun** - Fast JavaScript runtime, bundler, test runner, and package manager
- **caddy-mdrv** - Caddy web server with extra modules
- **mdrv-bt** - Sync Windows Bluetooth pairing keys into the BlueZ store (dual-boot, no re-pairing; static musl binary from GitHub releases)
- **mdrv-oc** - OpenCode session database manager (list, move, export/import, inspect sessions)
- **surrealdb** - Scalable, distributed, collaborative document-graph database
- **turso** - In-process SQL database engine compatible with SQLite

## Package Signing

Packages are **unsigned**. Add `SigLevel = Optional TrustAll` in `/etc/pacman.conf`.

## Building

Packages are automatically built on GitHub Actions:

- **aarch64**: native ARM runners (`ubuntu-24.04-arm`) with `archlinuxarm:base-devel`
- **x86_64**: standard runners (`ubuntu-latest`) with `archlinux:base-devel`

## License

Each package follows its own license. See individual package sources for details.
