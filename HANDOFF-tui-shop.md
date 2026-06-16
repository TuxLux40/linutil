# Handoff: TUI Shop Integration

## What this is

Oliver forked [Gcat101/tui-shop](https://github.com/Gcat101/tui-shop) on 2026-06-16 as [TuxLux40/tui-shop](https://github.com/TuxLux40/tui-shop).

**tui-shop** is a TUI app store: a menu-driven installer specifically for CLI/TUI tools. "Something between a GUI and a CLI way of downloading apps." Written in Python, installs via `/opt/tui-shop/`, driven by a `config.json` with a GitHub API key for fetching release metadata.

This is the deferred TUI dashboard item from the linutil session — instead of building a custom table-renderer from scratch, tui-shop already provides:
- Browse/search TUI tools
- One-command install from within the TUI
- Install status tracking

## Intent

Wire tui-shop into linutil as an entry under a new **TUI Tools** section (or under Applications Setup), similar to how ClamUI or other GUI wrappers are handled. A linutil script would install tui-shop itself, then optionally pre-populate it with Oliver's curated list below.

## Oliver's curated TUI list (from terminaltrove.com research, 2026-06-16)

Sourced from open browser tabs on terminaltrove.com. These are the tools Oliver was evaluating — candidates for pre-seeding into tui-shop or a custom toollist.

### AI / LLM
- [oterm](https://terminaltrove.com/oterm/) — Ollama TUI
- [gollama](https://terminaltrove.com/gollama/) — Manage Ollama models

### Shells / Navigation
- [zoxide](https://terminaltrove.com/zoxide/) — Smarter cd
- [navi](https://terminaltrove.com/navi/) — Interactive cheatsheet tool
- [up](https://terminaltrove.com/up/) — Pipe explorer with live preview
- [pet](https://terminaltrove.com/pet/) — CLI snippet manager
- [intelli-shell](https://terminaltrove.com/intelli-shell/) — Shell command bookmarks
- [qo](https://terminaltrove.com/qo/) — Quick open

### Git / Dev
- [lazygit](https://terminaltrove.com/lazygit/) — Git TUI
- [lazynpm](https://terminaltrove.com/lazynpm/) — npm TUI
- [lazyenv](https://terminaltrove.com/lazyenv/) — Env variable manager
- [gh-dash](https://terminaltrove.com/gh-dash/) — GitHub dashboard
- [scooter](https://terminaltrove.com/scooter/) — Interactive find-and-replace
- [vscli](https://terminaltrove.com/vscli/) — VS Code launcher TUI

### Data / Files
- [visidata](https://terminaltrove.com/visidata/) — Tabular data explorer
- [miller](https://terminaltrove.com/miller/) — CSV/JSON/TSV processor
- [xsv](https://terminaltrove.com/xsv/) — Fast CSV toolkit
- [qsv](https://terminaltrove.com/qsv/) — qsv (xsv fork with more features)
- [pdu](https://terminaltrove.com/pdu/) — Disk usage TUI
- [pdfgrep](https://terminaltrove.com/pdfgrep/) — Search PDFs from terminal
- [wiper](https://terminaltrove.com/wiper/) — Secure file wiper
- [nap](https://terminaltrove.com/nap/) — Code snippet manager

### Networking / Security
- [termshark](https://terminaltrove.com/termshark/) — Wireshark-like TUI
- [rustscan](https://terminaltrove.com/rustscan/) — Fast port scanner
- [mtr](https://terminaltrove.com/mtr/) — Network diagnostic (ping + traceroute)
- [netop](https://terminaltrove.com/netop/) — Network topology viewer
- [netwatch](https://terminaltrove.com/netwatch/) — Network monitor
- [netshow](https://terminaltrove.com/netshow/) — Network interface info
- [kyanos](https://terminaltrove.com/kyanos/) — Network traffic analyzer
- [tcpterm](https://terminaltrove.com/tcpterm/) — TCP traffic TUI
- [tcpdump](https://terminaltrove.com/tcpdump/) — Packet capture (classic)
- [tufw](https://terminaltrove.com/tufw/) — UFW firewall TUI
- [snitch](https://terminaltrove.com/snitch/) — Network connection monitor
- [mdns-scanner](https://terminaltrove.com/mdns-scanner/) — mDNS network scanner
- [whosthere](https://terminaltrove.com/whosthere/) — SSH login notifier
- [wifitui](https://terminaltrove.com/wifitui/) — WiFi manager TUI
- [osintui](https://terminaltrove.com/osintui/) — OSINT TUI
- [sherlock](https://terminaltrove.com/sherlock/) — Username OSINT
- [threatdeck](https://terminaltrove.com/threatdeck/) — Threat intel dashboard

### System / Monitoring
- [tiptop](https://terminaltrove.com/tiptop/) — htop-like resource monitor
- [vtop](https://terminaltrove.com/vtop/) — Graphical activity monitor
- [syswatch](https://terminaltrove.com/syswatch/) — System watcher
- [kmon](https://terminaltrove.com/kmon/) — Kernel module manager
- [systemctl-tui](https://terminaltrove.com/systemctl-tui/) — systemctl TUI
- [systemd-manager-tui](https://terminaltrove.com/systemd-manager-tui/) — systemd unit manager
- [strace-tui](https://terminaltrove.com/strace-tui/) — strace with TUI
- [pvetui](https://terminaltrove.com/pvetui/) — Proxmox VE TUI
- [hyprmoncfg](https://terminaltrove.com/hyprmoncfg/) — Hyprland monitor config

### Databases
- [gobang](https://terminaltrove.com/gobang/) — Multi-DB TUI client
- [pgcli](https://terminaltrove.com/pgcli/) — PostgreSQL CLI with autocomplete
- [vi-mongo](https://terminaltrove.com/vi-mongo/) — MongoDB TUI

### Media / Web
- [youtube-tui](https://terminaltrove.com/youtube-tui/) — YouTube TUI
- [yt-dlp](https://terminaltrove.com/yt-dlp/) — Video downloader
- [lynx](https://terminaltrove.com/lynx/) — Text-mode browser
- [steamfetch](https://terminaltrove.com/steamfetch/) — Steam library fetch info

### Comms
- [aerc](https://terminaltrove.com/aerc/) — Email client TUI
- [endcord](https://terminaltrove.com/endcord/) — Discord TUI
- [gurk](https://terminaltrove.com/gurk/) — Signal TUI
- [msgvault](https://terminaltrove.com/msgvault/) — Message archiver

### Docs / Help
- [tldr-pages](https://terminaltrove.com/tldr-pages/) — Simplified man pages
- [manly](https://terminaltrove.com/manly/) — man page search TUI
- [qman](https://terminaltrove.com/qman/) — man page TUI
- [wikiman](https://terminaltrove.com/wikiman/) — Offline wiki + man pages
- [wiki-tui](https://terminaltrove.com/wiki-tui/) — Wikipedia TUI
- [openapi-tui](https://terminaltrove.com/openapi-tui/) — OpenAPI spec explorer

### Misc / Fun
- [wtf](https://terminaltrove.com/wtf/) — Personal dashboard
- [crates-tui](https://terminaltrove.com/crates-tui/) — Browse crates.io
- [quokka](https://terminaltrove.com/quokka/) — JS/TS REPL
- [rura](https://terminaltrove.com/rura/) — Rust TUI framework demo
- [rustormy](https://terminaltrove.com/rustormy/) — Rust-based stormy weather
- [see-tui](https://terminaltrove.com/see-tui/) — Code explorer
- [surge](https://terminaltrove.com/surge/) — HTTP testing TUI
- [squall](https://terminaltrove.com/squall/) — HTTP stress tester
- [taproom](https://terminaltrove.com/taproom/) — Homebrew tap manager
- [twig](https://terminaltrove.com/twig/) — Git branch manager
- [ugm](https://terminaltrove.com/ugm/) — User/group manager
- [uuinfo](https://terminaltrove.com/uuinfo/) — System info display
- [lue](https://terminaltrove.com/lue/) — Lua env explorer
- [wakey](https://terminaltrove.com/wakey/) — WakeOnLan TUI
- [fztea](https://terminaltrove.com/fztea/) — Flipper Zero TUI
- [moribito](https://terminaltrove.com/moribito/) — Habit tracker
- [pathos](https://terminaltrove.com/pathos/) — PATH manager
- [passepartui](https://terminaltrove.com/passepartui/) — pass password manager TUI
- [quien](https://terminaltrove.com/quien/) — who/w replacement
- [gruyere](https://terminaltrove.com/gruyere/) — Cheese (fun)
- [ggh](https://terminaltrove.com/ggh/) — GitHub PR/issue launcher
- [rizin](https://terminaltrove.com/rizin/) — Reverse engineering framework
- [radare2](https://terminaltrove.com/radare2/) — Reverse engineering
- [recoverpy](https://terminaltrove.com/recoverpy/) — Recover deleted files
- [nerdlog](https://terminaltrove.com/nerdlog/) — Log viewer
- [sidecar](https://terminaltrove.com/sidecar/) — k8s sidecar manager
- [wintui](https://terminaltrove.com/wintui/) — Windows-style TUI (WSL)
- [google-workspace-cli](https://terminaltrove.com/google-workspace-cli/) — Google Workspace CLI
- [chmod-cli](https://terminaltrove.com/chmod-cli/) — chmod helper TUI
- [shellcheck](https://terminaltrove.com/shellcheck/) — Shell script linter
- [tio](https://terminaltrove.com/tio/) — Serial port TUI

## Next steps

1. Evaluate tui-shop upstream maturity — it's Python + config.json, last active ~2022. May need modernization (uv, updated package sources).
2. Decide: extend tui-shop with the list above, or just add a `tui-shop-setup.sh` entry to linutil under Applications → Tools.
3. The terminaltrove list above is raw/unfiltered — trim to what Oliver actually wants installed, then that becomes the seed list.
