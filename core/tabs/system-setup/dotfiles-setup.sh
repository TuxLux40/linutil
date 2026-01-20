#!/bin/sh -e

. ../common-script.sh

# Find the linutil repo root (where this script is located)
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
DOTFILES_DIR="$REPO_ROOT/dotfiles"

list_dotfiles() {
    if [ ! -d "$DOTFILES_DIR" ]; then
        printf "%b\n" "${RED}Dotfiles directory not found at $DOTFILES_DIR${RC}"
        exit 1
    fi
    
    cd "$DOTFILES_DIR" || exit 1
    printf "%b\n" "${CYAN}Available dotfiles packages:${RC}"
    i=1
    for dir in */; do
        if [ -d "$dir" ]; then
            package="${dir%/}"
            printf "%b. %b\n" "$i" "$package"
            i=$((i + 1))
        fi
    done
}

select_dotfiles() {
    printf "%b\n" "${YELLOW}Which dotfiles do you want to symlink?${RC}"
    printf "%b\n" "${CYAN}Enter package names separated by spaces (or 'all' for all packages):${RC}"
    read -r selection

    printf "%b\n" "${YELLOW}Existing config files will be backed up to ~/.config-backup${RC}"
    printf "%b\n" "${YELLOW}Continue? (y/n):${RC}"
    read -r backup_choice
    
    if [ "$backup_choice" != "y" ] && [ "$backup_choice" != "Y" ]; then
        printf "%b\n" "${RED}Aborted.${RC}"
        return
    fi

    # Create backup directory
    BACKUP_DIR="$HOME/.config-backup-$(date +%Y%m%d-%H%M%S)"
    mkdir -p "$BACKUP_DIR"

    cd "$DOTFILES_DIR" || exit 1

    if [ "$selection" = "all" ]; then
        for dir in */; do
            if [ -d "$dir" ]; then
                package="${dir%/}"
                printf "%b\n" "${YELLOW}Stowing $package from repo to $HOME...${RC}"
                backup_conflicts "$package"
                stow -v "$package" -t "$HOME" 2>&1 | grep -v "BUG in find_stowed_path" || true
            fi
        done
    else
        for package in $selection; do
            if [ -d "$package" ]; then
                printf "%b\n" "${YELLOW}Stowing $package from repo to $HOME...${RC}"
                backup_conflicts "$package"
                stow -v "$package" -t "$HOME" 2>&1 | grep -v "BUG in find_stowed_path" || true
            else
                printf "%b\n" "${RED}Package '$package' not found!${RC}"
            fi
        done
    fi

    printf "%b\n" "${GREEN}Dotfiles symlinked successfully!${RC}"
    printf "%b\n" "${CYAN}Repository configs (source of truth) are now linked to $HOME${RC}"
    printf "%b\n" "${YELLOW}Backup saved to: $BACKUP_DIR${RC}"
}

backup_conflicts() {
    package="$1"
    # Check for conflicts and backup existing files
    stow -n "$package" -t "$HOME" 2>&1 | grep "existing target" | while read -r line; do
        # Extract filename from error message
        file=$(echo "$line" | sed -n 's/.*existing target \(.*\) since.*/\1/p')
        if [ -n "$file" ] && [ -e "$HOME/$file" ] && [ ! -L "$HOME/$file" ]; then
            printf "%b\n" "${YELLOW}  Backing up: $file${RC}"
            mkdir -p "$BACKUP_DIR/$(dirname "$file")"
            mv "$HOME/$file" "$BACKUP_DIR/$file"
        fi
    done
}

unstow_dotfiles() {
    printf "%b\n" "${YELLOW}Do you want to remove/unstow any dotfiles? (y/n):${RC}"
    read -r unstow_choice
    
    if [ "$unstow_choice" = "y" ] || [ "$unstow_choice" = "Y" ]; then
        cd "$DOTFILES_DIR" || exit 1
        printf "%b\n" "${CYAN}Enter package names to remove (separated by spaces):${RC}"
        read -r packages_to_remove
        
        for package in $packages_to_remove; do
            if [ -d "$package" ]; then
                printf "%b\n" "${YELLOW}Unstowing $package from $HOME...${RC}"
                stow -D -v "$package" -t "$HOME" 2>&1 | grep -v "BUG in find_stowed_path" || true
            else
                printf "%b\n" "${RED}Package '$package' not found!${RC}"
            fi
        done
        printf "%b\n" "${GREEN}Done removing symlinks!${RC}"
    fi
}

main() {
    printf "%b\n" "${CYAN}==================================${RC}"
    printf "%b\n" "${CYAN}    Dotfiles Management (stow)   ${RC}"
    printf "%b\n" "${CYAN}==================================${RC}"
    printf "%b\n" "${YELLOW}Dotfiles location: $DOTFILES_DIR${RC}"

    # Check if stow is installed
    if ! command_exists stow; then
        printf "%b\n" "${YELLOW}GNU stow is not installed.${RC}"
        install_stow
    fi

    # List available dotfiles
    list_dotfiles

    # Select and stow dotfiles
    select_dotfiles

    # Option to unstow
    unstow_dotfiles

    printf "%b\n" "${GREEN}Done!${RC}"
}

checkEnv
checkEscalationTool
main
