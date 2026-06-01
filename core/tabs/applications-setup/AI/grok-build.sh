#!/bin/sh -e

. ../../common-script.sh

checkRoot() {
    if [ "$(id -u)" -eq 0 ]; then
        printf "%b\n" "${RED}This script should not be run as root!${RC}"
        exit 1
    fi
}

installGrok() {
    if command_exists grok; then
        printf "%b\n" "${GREEN}Grok CLI is already installed: $(grok --version 2>/dev/null || echo 'unknown version')${RC}"
        printf "%b" "${YELLOW}Do you want to update Grok CLI? [y/N] ${RC}"
        read -r update_choice
        case "$update_choice" in
        y | Y)
            printf "%b\n" "${CYAN}Updating Grok CLI...${RC}"
            curl -fsSL https://x.ai/cli/install.sh | bash
            printf "%b\n" "${GREEN}Grok CLI updated successfully.${RC}"
            ;;
        *)
            printf "%b\n" "${CYAN}Skipping update.${RC}"
            ;;
        esac
    else
        printf "%b\n" "${CYAN}Installing Grok CLI...${RC}"
        curl -fsSL https://x.ai/cli/install.sh | bash
        printf "%b\n" "${GREEN}Grok CLI installed successfully.${RC}"
        printf "%b\n" "${YELLOW}Run 'grok' to get started. You will be prompted to authenticate on first launch.${RC}"
    fi
}

checkEnv
checkRoot
installGrok