# Linutil (Personal Fork)

![Preview](/.github/preview.gif)

This is a personal fork of [ChrisTitusTech/linutil](https://github.com/ChrisTitusTech/linutil). For the official version and upstream development, please visit the original repository.

**Linutil** is a distro-agnostic toolbox designed to simplify everyday Linux tasks. It helps you set up applications and optimize your system for specific use cases. I have updated it with my own dotfiles, programs and scripts I use. It is an awesome framework to adapt for your own usage and build upon.

## ⬇️ Installation

### First Time Setup

Clone and install:

```bash
git clone https://github.com/TuxLux40/linutil
cd linutil
cargo install --path ./tui
```

This installs the binary to `~/.cargo/bin/linutil`. Make sure `~/.cargo/bin` is in your `$PATH`.

### Update

To update to the latest version:

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

```bash
linutil
```

View available options:

```bash
linutil --help
```

## 📝 Configuration

Linutil supports configuration through a TOML config file. Specify the path with `--config` (or `-c`).

Available options:

- `auto_execute` - List of commands to execute automatically
- `skip_confirmation` - Skip confirmation prompts (Boolean)
- `size_bypass` - Bypass terminal size checks (Boolean)

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

Usage:

```bash
linutil --config /path/to/example_config.toml
```

## 📄 License

MIT - See [LICENSE](LICENSE) file for details.

Original project by [Chris Titus Tech](https://github.com/ChrisTitusTech/linutil)
