#!/bin/sh -e

. ../common-script.sh

# Dotfiles are always in the linutil repo under dotfiles/
DOTFILES_DIR="$HOME/git/linutil/dotfiles"

main() {
    # Verify dotfiles directory exists
    if [ ! -d "$DOTFILES_DIR" ]; then
        printf "%b\n" "${RED}Dotfiles directory not found at $DOTFILES_DIR${RC}"
        exit 1
    fi

    # Ensure GNU stow is installed
    if ! command_exists stow; then
        printf "%b\n" "${YELLOW}GNU stow is not installed.${RC}"
        install_stow
    fi

    printf "%b\n" "${YELLOW}Note: Existing config files will be deleted and replaced with repo versions.${RC}"
    printf "%b\n" "${YELLOW}No backups will be created - repo is source of truth.${RC}"
    printf "%b\n" "${CYAN}Stowing all dotfiles to $HOME...${RC}"
    
    cd "$DOTFILES_DIR" || exit 1
    
    # Loop through each package directory and stow it
    for dir in */; do
        if [ -d "$dir" ]; then
            package="${dir%/}"
            printf "%b\n" "${YELLOW}  • $package${RC}"
            # Remove old symlinks first
            stow -D "$package" -t "$HOME" 2>/dev/null || true
            # Force overwrite: adopt conflicts then restore repo version immediately
            # This deletes existing files and creates symlinks to repo (no backups)
            stow --adopt "$package" -t "$HOME" 2>&1 | grep -v "BUG in find_stowed_path" || true
        fi
    done
    
    # Restore repo versions (repo is source of truth, local changes discarded)
    git restore . 2>/dev/null || true

    printf "%b\n" "${GREEN}Done!${RC}"
}

checkEnv
checkEscalationTool
main
