#!/bin/sh -e

. ../common-script.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

installYay() {
    if command_exists yay; then
        printf "%b\n" "${CYAN}yay is already installed.${RC}"
        return 0
    fi
    if ! command_exists pacman; then
        printf "%b\n" "${YELLOW}yay is Arch-only — skipping.${RC}"
        return 0
    fi
    printf "%b\n" "${YELLOW}Installing yay...${RC}"
    (cd "$SCRIPT_DIR/arch" && sh yay-setup.sh)
}

installParu() {
    if command_exists paru; then
        printf "%b\n" "${CYAN}paru is already installed.${RC}"
        return 0
    fi
    if ! command_exists pacman; then
        printf "%b\n" "${YELLOW}paru is Arch-only — skipping.${RC}"
        return 0
    fi
    printf "%b\n" "${YELLOW}Installing paru...${RC}"
    (cd "$SCRIPT_DIR/arch" && sh paru-setup.sh)
}

installFlatpak() {
    if command_exists flatpak && flatpak remotes 2>/dev/null | grep -q flathub; then
        printf "%b\n" "${CYAN}Flatpak with Flathub is already set up.${RC}"
        return 0
    fi
    printf "%b\n" "${YELLOW}Installing Flatpak + Flathub...${RC}"
    (cd "$SCRIPT_DIR/../applications-setup" && sh setup-flatpak.sh)
}

installHomebrew() {
    if command_exists brew; then
        printf "%b\n" "${CYAN}Homebrew is already installed.${RC}"
        return 0
    fi
    printf "%b\n" "${YELLOW}Installing Homebrew (Linuxbrew)...${RC}"
    NONINTERACTIVE=1 bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Determine brew prefix (may be /home/linuxbrew/.linuxbrew or ~/.linuxbrew)
    BREW_PREFIX=""
    if [ -x "/home/linuxbrew/.linuxbrew/bin/brew" ]; then
        BREW_PREFIX="/home/linuxbrew/.linuxbrew"
    elif [ -x "$HOME/.linuxbrew/bin/brew" ]; then
        BREW_PREFIX="$HOME/.linuxbrew"
    fi

    if [ -n "$BREW_PREFIX" ]; then
        # bash
        if [ -f "$HOME/.bashrc" ]; then
            grep -q 'brew shellenv' "$HOME/.bashrc" 2>/dev/null || \
                printf '\neval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX" >> "$HOME/.bashrc"
        fi
        # zsh
        if [ -f "$HOME/.zshrc" ]; then
            grep -q 'brew shellenv' "$HOME/.zshrc" 2>/dev/null || \
                printf '\neval "$(%s/bin/brew shellenv)"\n' "$BREW_PREFIX" >> "$HOME/.zshrc"
        fi
        # fish
        FISH_CONF="$HOME/.config/fish/conf.d"
        if [ -d "$FISH_CONF" ]; then
            printf '%s/bin/brew shellenv | source\n' "$BREW_PREFIX" > "$FISH_CONF/homebrew.fish"
        fi
        printf "%b\n" "${GREEN}Homebrew installed. Restart your shell or source your config to use 'brew'.${RC}"
    else
        printf "%b\n" "${YELLOW}Homebrew installed but prefix not found — add it to PATH manually.${RC}"
    fi
}

checkEnv
checkEscalationTool

installYay
installParu
installFlatpak
installHomebrew
