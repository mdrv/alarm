# Arch Linux ARM (aarch64) Repository

Personal Arch Linux ARM (aarch64) package repository built on GitHub Actions.

## Usage

Add to `/etc/pacman.conf`:

```ini
[mdrv]
SigLevel = Required DatabaseOptional TrustedOnly
Server = https://mdrv.github.io/alarm/aarch64
```

Then update and install:

```bash
sudo pacman -Syu
sudo pacman -S mdrv/bun
sudo pacman -S mdrv/tofi
```

## Package Signing

All packages and repository database are signed with GPG. To use this repository securely:

1. **Import the repository key**:

```bash
# Using pacman-key
sudo pacman-key --recv-keys D93EF7B1DAC1910BCBC8B8A08F6852C610B71619

# OR from key file
wget https://mdrv.github.io/alarm/mdrv-key.asc
sudo pacman-key --add mdrv-key.asc
```

2. **Verify the fingerprint**:

```bash
sudo pacman-key --finger D93EF7B1DAC1910BCBC8B8A08F6852C610B71619
```

The fingerprint should match:
```
D93E F7B1 DAC1 910C BCBC 8B8A 08F6 852C 610B 7161 9
```

3. **Locally sign the key to trust it**:

```bash
sudo pacman-key --lsign-key D93EF7B1DAC1910BCBC8B8A08F6852C610B71619
```

Now packages signed by this key will be accepted with `SigLevel = TrustedOnly`.

**Security Note**: `TrustAll` is not recommended. Use `TrustedOnly` with locally signed keys for proper security.

## Available Packages

- **bun** - Fast JavaScript runtime, bundler, test runner, and package manager (prebuilt binary from official releases)
- **tofi** - Tiny rofi / dmenu replacement for wlroots-based Wayland compositors

## Building

Packages are automatically built on GitHub Actions using native ARM64 runners (ubuntu-24.04-arm).

## License

Each package follows its own license. See individual package sources for details.
