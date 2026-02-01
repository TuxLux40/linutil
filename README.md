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
