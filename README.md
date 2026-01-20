# Chris Titus Tech's Linux Utility (Personal Fork)

![Preview](/.github/preview.gif)

**Linutil** is a distro-agnostic toolbox designed to simplify everyday Linux tasks. It helps you set up applications and optimize your system for specific use cases. The utility is actively developed in Rust 🦀, providing performance and reliability.

## ⬇️ Installation

### First Time Setup

Clone and install:

```bash
git clone https://github.com/<your-username>/linutil
cd linutil
cargo install --path ./tui
```

This installs the binary to `~/.cargo/bin/linutil`. Make sure `~/.cargo/bin` is in your `$PATH`.

### Update

To update to the latest version from your fork:

```bash
linutil update
```

Or manually:

```bash
cd ~/git/linutil
git pull
cargo install --path ./tui
```

## 💡 Usage

Run linutil:

```bash
linutil
```

### CLI arguments

View available options:

```bash
linutil --help
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
