#!/bin/sh -e

. ../common-script.sh

installAtuin() {
    printf "%b\n" "${YELLOW}Installing Atuin...${RC}"
    curl --proto '=https' --tlsv1.2 -LsSf https://setup.atuin.sh | sh

    printf "%b\n" "${YELLOW}Importing shell history from all detected shells...${RC}"
    atuin import auto

    # Fish shell integration — bash/zsh are handled automatically by the Atuin installer
    FISH_CONF="$HOME/.config/fish/conf.d"
    if [ -d "$FISH_CONF" ] && ! grep -qr 'atuin init fish' "$FISH_CONF" 2>/dev/null; then
        printf 'atuin init fish | source\n' > "$FISH_CONF/atuin.fish"
        printf "%b\n" "${GREEN}Fish shell integration installed.${RC}"
    fi

    printf "%b\n" "${GREEN}Atuin installed. Restart your terminal or re-source your shell config to activate.${RC}"
}

checkEnv
installAtuin
