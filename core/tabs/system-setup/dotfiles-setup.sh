#!/bin/sh -e

. ../common-script.sh

DOTFILES_REPO="${DOTFILES_REPO:-https://github.com/TuxLux40/dotfiles.git}"
DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"

install_git() {
    case "$PACKAGER" in
        pacman)       "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm git ;;
        apk)          "$ESCALATION_TOOL" "$PACKAGER" add git ;;
        xbps-install) "$ESCALATION_TOOL" "$PACKAGER" -Sy git ;;
        *)            "$ESCALATION_TOOL" "$PACKAGER" install -y git ;;
    esac
}

main() {
    if ! command_exists git; then
        printf "%b\n" "${YELLOW}git not installed, installing...${RC}"
        install_git
    fi

    if [ -d "$DOTFILES_DIR/.git" ]; then
        printf "%b\n" "${CYAN}Updating dotfiles repo at $DOTFILES_DIR${RC}"
        git -C "$DOTFILES_DIR" pull --ff-only
    elif [ -e "$DOTFILES_DIR" ]; then
        printf "%b\n" "${RED}$DOTFILES_DIR exists and is not a git checkout${RC}"
        exit 1
    else
        printf "%b\n" "${CYAN}Cloning $DOTFILES_REPO -> $DOTFILES_DIR${RC}"
        git clone --depth=1 "$DOTFILES_REPO" "$DOTFILES_DIR"
    fi

    if [ ! -x "$DOTFILES_DIR/install.sh" ] && [ ! -f "$DOTFILES_DIR/install.sh" ]; then
        printf "%b\n" "${RED}install.sh missing in $DOTFILES_DIR${RC}"
        exit 1
    fi

    printf "%b\n" "${YELLOW}Note: repo is source of truth. Existing local config files will be replaced with repo versions.${RC}"
    sh "$DOTFILES_DIR/install.sh"
}

checkEnv
checkEscalationTool
main
