This fork of **CTTs Linutil** has been adapted to my needs and to manage my dotfiles. Any credit and [feedback](https://github.com/ChrisTitusTech/linutil/issues) should go upstream.

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

For comprehensive information on how to use Linutil, visit the [Linutil Official Documentation](https://linutil.christitus.com/).

## 🛠 Contributing

We welcome contributions from the community! Before you start, please review our [Contributing Guidelines](.github/CONTRIBUTING.md) to understand how to make the most effective and efficient contributions.

Docs are now [here](https://github.com/Chris-Titus-Docs/linutil-docs)

## 🏅 Thanks to All Contributors

Thank you to everyone who has contributed to the development of Linutil. Your efforts are greatly appreciated, and you're helping make this tool better for everyone!

[![Contributors](https://contrib.rocks/image?repo=ChrisTitusTech/linutil)](https://github.com/ChrisTitusTech/linutil/graphs/contributors)

## 📜 Contributor Milestones

- 2024/07 - Original Linutil Rust TUI was developed by [@JustLinuxUser](https://github.com/JustLinuxUser).
- 2024/09 - TabList (Left Column) and various Rust Core/TUI Improvements developed by [@lj3954](https://github.com/lj3954)
- 2024/09 - Cargo Publish, AUR, Rust, and Bash additions done by [@koibtw](https://github.com/koibtw)
- 2024/09 - Rust TUI Min/Max, MultiSelection, and Bash additions done by [@jeevithakannan2](https://github.com/jeevithakannan2)
- 2024/09 - Various bash updates and standardization done by [@nnyyxxxx](https://github.com/nnyyxxxx)
- 2024/09 - Multiple bash script additions done by [@guruswarupa](https://github.com/guruswarupa)
- 2026/01 - TUI Refresh with Logo by [@Abs313a](https://github.com/Abs313a)
- 2026/03 - Linutil docs website creation by [@seanh1995](https://github.com/seanh1995)
