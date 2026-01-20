# Linutil Dotfiles

Dieses Verzeichnis enthält Konfigurationsdateien für verschiedene Tools und Desktop-Umgebungen.

## Struktur

Alle dotfiles sind für die Verwendung mit **GNU stow** strukturiert. Jeder Unterordner ist ein "stow package":

```
dotfiles/
├── aichat/       # AI Chat Konfiguration
├── atuin/        # Shell History Manager
├── fastfetch/    # System Info Tool
├── fish/         # Fish Shell
├── ghostty/      # Ghostty Terminal
├── kde/          # KDE Plasma Konfiguration
├── starship/     # Starship Prompt
└── ...
```

## Verwendung mit GNU stow

### Über linutil (empfohlen)

Nutze das "Dotfiles Management" Skript in linutil unter **System Setup**:

```bash
./linutil
# Navigiere zu: System Setup → Dotfiles Management
```

### Manuell

```bash
cd dotfiles

# Einzelnes Package symlinken
stow -t ~ kde

# Mehrere Packages
stow -t ~ fish starship ghostty

# Alle Packages
stow -t ~ */

# Package entfernen
stow -D -t ~ kde
```

### Mit --adopt (vorhandene Configs übernehmen)

Falls du bereits Configs hast, kannst du diese mit `--adopt` ins Repo übernehmen:

```bash
stow --adopt -t ~ kde
# Deine bestehenden Configs werden ins Repo verschoben und dann verlinkt
```

## Package Details

- **kde**: Vollständige KDE Plasma Konfiguration (kdeglobals, kwinrc, dolphinrc, etc.)
- **fish**: Fish Shell Konfiguration mit Synology-spezifischer Variante
- **starship**: Starship Prompt Konfiguration
- **ghostty**: Ghostty Terminal Emulator
- **fastfetch**: System Info Display (mit arch.png)
- **atuin**: Shell History mit Sync
- **aichat**: AI Chat CLI Tool

## Hinweise

- Stow erstellt **Symlinks**, keine Kopien
- Änderungen in `~/.config/*` ändern direkt die Repo-Dateien
- Vor dem Symlinken: Sichere deine bestehenden Configs!
- Nutze `--adopt` um bestehende Configs zu übernehmen

## Tipps

```bash
# Simulation (dry-run)
stow -n -v -t ~ kde

# Konflikte auflösen mit --adopt
stow --adopt -t ~ kde

# Neu-symlinken nach Updates
stow -R -t ~ kde
```
