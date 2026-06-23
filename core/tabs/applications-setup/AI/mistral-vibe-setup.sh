#!/bin/sh -e

. ../../common-script.sh

checkRoot() {
    if [ "$(id -u)" -eq 0 ]; then
        printf "%b\n" "${RED}This script should not be run as root!${RC}"
        exit 1
    fi
}

installMistralVibe() {
    if command_exists vibe; then
        printf "%b\n" "${GREEN}Mistral Vibe is already installed: $(vibe --version 2>/dev/null || echo 'unknown version')${RC}"
        printf "%b" "${YELLOW}Do you want to update Mistral Vibe? [y/N] ${RC}"
        read -r update_choice
        case "$update_choice" in
        y | Y)
            printf "%b\n" "${CYAN}Updating Mistral Vibe...${RC}"
            curl -LsSf https://mistral.ai/vibe/install.sh | bash
            printf "%b\n" "${GREEN}Mistral Vibe updated successfully.${RC}"
            ;;
        *)
            printf "%b\n" "${CYAN}Skipping update.${RC}"
            ;;
        esac
    else
        printf "%b\n" "${CYAN}Installing Mistral Vibe...${RC}"
        curl -LsSf https://mistral.ai/vibe/install.sh | bash
        printf "%b\n" "${GREEN}Mistral Vibe installed successfully.${RC}"
        printf "%b\n" "${YELLOW}Run 'vibe' to get started. You will be prompted to log in on first launch.${RC}"
    fi
}

checkEnv
checkRoot
installMistralVibe
