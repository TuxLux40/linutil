#!/bin/sh -e

. ../common-script.sh

# Resolve the dotfiles directory relative to script location
# This works both when run directly and from the TUI
DOTFILES_DIR="$(dirname "$(dirname "$(dirname "$(realpath "$0")")")")/dotfiles"

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

    printf "%b\n" "${CYAN}Stowing all dotfiles to $HOME...${RC}"
    
    cd "$DOTFILES_DIR" || exit 1
    
    # Loop through each package directory and stow it
    # Each subdirectory in dotfiles/ is treated as a separate stow package
    for dir in */; do
        if [ -d "$dir" ]; then
            package="${dir%/}"
            printf "%b\n" "${YELLOW}  • $package${RC}"
            # Create symlinks from package to $HOME, suppress stow warnings
            stow -v "$package" -t "$HOME" 2>&1 | grep -v "BUG in find_stowed_path" || true
        fi
    done

    printf "%b\n" "${GREEN}Done!${RC}"
}

checkEnv
checkEscalationTool
main
