# Linutil (TuxLux40 fork)

This fork of **CTTs Linutil** has been adapted to my needs and to manage my dotfiles. Any credit and [feedback](https://github.com/ChrisTitusTech/linutil/issues) should go upstream.

## 🚀 Install

### Pi 3 / aarch64 (precompiled, no build)

```sh
curl -fsSL https://raw.githubusercontent.com/TuxLux40/linutil/main/install-pi.sh | sh
```

Lädt `linutil-aarch64` aus dem letzten Release und legt es nach `/usr/local/bin/linutil`. Works on Raspberry Pi OS 64-bit, Ubuntu ARM64, any glibc-based aarch64 distro.

### x86_64 / aarch64 (upstream installer)

```sh
curl -fsSL https://christitus.com/linux | sh
```

### Build locally (cross-compile aarch64 from x86_64 dev box)

```sh
sudo pacman -S aarch64-linux-gnu-gcc   # Arch/CachyOS
./build-pi.sh --release                # build + upload to GH release
```

## 💡 Usage

### CLI arguments

View available options by running:

```bash
linutil --help
```

For installer options:

```bash
curl -fsSL https://christitus.com/linux | sh -s -- --help
```

## Configuration

Linutil supports configuration through a TOML config file. Path to the file can be specified with `--config` (or `-c`).

Available options:

- `auto_execute` - A list of commands to execute automatically (can be combined with `--skip-confirmation`)
- `skip_confirmation` - Boolean ( Equal to `--skip-confirmation`)
- `size_bypass` - Boolean ( Equal to `--size-bypass` )

Example config:

```toml
# example_config.toml

auto_execute = [
    "Fastfetch",
    "Alacritty",
    "Kitty"
]

skip_confirmation = true
size_bypass = true
```

```bash
linutil --config /path/to/example_config.toml
```

## 🎓 Documentation

Repo docs, troubleshooting guides and my homelab documentation can be found in the [wiki of this repo](https://github.com/TuxLux40/linutil/wiki).
