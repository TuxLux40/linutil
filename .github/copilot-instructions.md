# Copilot Instructions for Linutil

## Project Overview

**Linutil** is a distro-agnostic Linux toolbox providing a TUI for system setup and optimization. It combines:
- **Rust TUI** (`tui/`): Interactive terminal interface using Ratatui
- **Rust Core** (`core/`): Command registry and configuration management  
- **Shell Scripts**: Organized under `core/tabs/` by category (applications, containers, gaming, security, system, utils)

### Architecture Pattern: Command Registry + Script Executor

The system uses a **declarative, tree-based command model**:

1. **Definition Layer**: Shell scripts in `core/tabs/` directories + `tabs.toml` metadata
2. **Core Layer** (`core/`): Parses tabs.toml, builds an `ego_tree::Tree<Rc<ListNode>>` where each leaf node is an executable command
3. **UI Layer** (`tui/`): Displays tree hierarchically; users select leaf nodes to execute commands

This separation allows:
- Adding new tools via `.sh` files without touching Rust code
- Validation of commands before UI rendering (`validate: bool` in `get_tabs()`)
- Config-driven command execution (`auto_execute` in TOML config)

## Key Files & Data Structures

### Core Registry
- `core/src/lib.rs`: Exports `Command` enum (Raw shell command, LocalFile script path, or None for directories) and `ListNode` struct (name, description, command, task_list, multi_select)
- `core/src/inner.rs`: `get_tabs()` function that:
  - Embeds shell scripts at compile time using `include_dir!("$CARGO_MANIFEST_DIR/tabs")`
  - Copies scripts to temp directory on runtime
  - Parses TOML metadata to build tree structure
  - Validates command existence if `validate=true`

### TUI State Management
- `tui/src/state.rs`: `AppState` holds the tab tree, current selection, execution state
- `tui/src/root.rs`: Primary render loop and navigation logic
- `tui/src/running_command.rs`: PTY-based command execution using `portable-pty`

### Script Helpers
- `core/tabs/common-script.sh`: Shared utilities for all scripts (escalation tool detection, package manager abstraction, Flatpak/AUR helper setup)
- `core/tabs/common-service-script.sh`: Systemd service helpers

## Development Workflows

### Build & Test
```bash
# Build release (optimized: LTO, strip, single codegen unit)
cargo build --release

# Run tests
cargo test

# Lint (warnings treated as errors)
cargo clippy -- -Dwarnings

# Format (check or fix)
cargo fmt --all --check  # Check only
cargo fmt --all          # Fix in-place

# Shell script linting
find core/tabs -name '*.sh' -exec shellcheck {} +
```

### Local Development
```bash
# Install locally (for testing)
cargo install --path ./tui

# Run TUI directly from source
cargo run -p linutil_tui -- [--config <path>] [--mouse]

# Run specific tests
cargo test --lib config::tests
```

### Adding New Tools

1. **Create shell script** in appropriate subdirectory under `core/tabs/`:
   ```bash
   # e.g., core/tabs/applications-setup/my-tool.sh
   #!/bin/bash
   source "../../common-script.sh"
   
   checkEscalationTool
   printf "%b\n" "Installing my tool..."
   ```

2. **Register in `tab_data.toml`** (in same directory):
   ```toml
   [[tabs]]
   name = "My Tool"
   description = "Does something useful"
   script = "my-tool.sh"
   task_list = ""  # Optional: comma-separated task IDs
   multi_select = false
   ```

3. **Build hierarchy** using `[[subtabs]]`:
   ```toml
   [[tabs]]
   name = "Category"
   [[tabs.subtabs]]
   name = "Tool"
   script = "tool.sh"
   ```

## Rust Code Patterns

### Imports & Module Style
- **Granularity**: Use `imports_granularity = "Crate"` (from `rustfmt.toml`) → prefer `use crate::*` over fine-grained imports
- **Order**: std → external crates → local modules
- **Module declarations**: List at file top: `mod modulename;`

### Error Handling
- Fallible operations return `Result<T>` (no custom error types currently)
- Script validation failures cause TUI to render empty (see `get_tabs()`)

### Workspace Structure
- **Boundary enforcement**: `core` is a library; `tui` depends on `core`; `xtask` is separate tooling
- **Shared Cargo.toml values** in `[workspace.package]`: version (25.12.18), edition (2021), license (MIT)
- **Default members**: tui, core (xtask excluded)

### Types & Traits
- **Tree structure**: Uses `ego_tree` crate; nodes hold `Rc<ListNode>` to enable sharing
- **Deref impls**: `TabList` derefs to `Vec<Tab>` for convenience (see inner.rs)
- **Command execution**: Uses `portable-pty` for PTY shells (allows interactive commands)

## Configuration & Runtime Behavior

### Config File (TOML Format)
```toml
auto_execute = ["Fastfetch", "Kitty"]  # Exact ListNode names
skip_confirmation = true
size_bypass = true
```

- Resolved via `Config::read_config(path, tabs)` which parses TOML and maps command names to `ListNode` references
- Used in `AppState` to drive execution flow

### Terminal & UI Conventions
- **Theme system**: Custom theme module; respects terminal colors
- **Mouse support**: Optional (enable via `--mouse` flag)
- **Terminal size checks**: Bypassable via config `size_bypass`
- **PTY updates**: Uses atomic `TERMINAL_UPDATED` flag to coordinate render/command threads

## Integration Points & Dependencies

### External Crates
- **TUI rendering**: `ratatui` (with crossterm backend) + `tui-term` for terminal emulation
- **Command execution**: `portable-pty` (pseudo-terminal) + oneshot channels for thread synchronization
- **Tree structure**: `ego_tree` (immutable tree with node references)
- **Config parsing**: `serde` + `toml`
- **Script embedding**: `include_dir` (compile-time inclusion of shell scripts)

### Package Manager Abstraction
Scripts detect and use available package managers via environment variables set in `common-script.sh`:
- `PACKAGER`: pacman, apt, dnf, zypper, apk, xbps-install, etc.
- `ESCALATION_TOOL`: sudo, doas, or eval (if root)
- `AUR_HELPER`: yay or paru (Arch-only)

## Testing & Validation

- **Unit tests**: In-crate (e.g., `core/src/lib.rs` contains tab tree search tests)
- **Temp directories**: Tests use `temp_dir` crate for isolation
- **Script validation**: `validate: bool` parameter in `get_tabs()` checks if commands exist before rendering (critical for distro compatibility)

## Common Gotchas

1. **Script embedding**: Changes to scripts in `core/tabs/` require **full recompilation** (uses `include_dir!`)
2. **Tab name matching**: `auto_execute` uses exact string matching against `ListNode.name`; if names change, configs break
3. **Escalation tool detection**: Scripts must call `checkEscalationTool` before running privileged commands (variable is global-scoped across sourced files)
4. **Distro-specific commands**: Always test with `validate=true` when adding tools that don't exist on all distros
