#!/bin/sh -e

. ../../common-script.sh

checkRoot() {
    if [ "$(id -u)" -eq 0 ]; then
        printf "%b\n" "${RED}This script should not be run as root!${RC}"
        exit 1
    fi
}

checkDependencies() {
    if ! command_exists gh; then
        printf "%b\n" "${RED}GitHub CLI ('gh') is required but not installed.${RC}"
        printf "%b\n" "${YELLOW}Install it via your package manager (e.g. 'sudo pacman -S github-cli') and re-run this script.${RC}"
        exit 1
    fi
}

installCopilot() {
    if gh extension list 2>/dev/null | grep -q "gh-copilot"; then
        printf "%b\n" "${GREEN}GitHub Copilot CLI extension is already installed.${RC}"
        printf "%b" "${YELLOW}Do you want to update it? [y/N] ${RC}"
        read -r update_choice
        case "$update_choice" in
        y | Y)
            printf "%b\n" "${CYAN}Updating GitHub Copilot CLI...${RC}"
            curl -fsSL https://gh.io/copilot-install | bash
            printf "%b\n" "${GREEN}GitHub Copilot CLI updated successfully.${RC}"
            ;;
        *)
            printf "%b\n" "${CYAN}Skipping update.${RC}"
            ;;
        esac
    else
        printf "%b\n" "${CYAN}Installing GitHub Copilot CLI...${RC}"
        curl -fsSL https://gh.io/copilot-install | bash
        printf "%b\n" "${GREEN}GitHub Copilot CLI installed successfully.${RC}"
        printf "%b\n" "${YELLOW}Run 'gh copilot' to get started. Authenticate with 'gh auth login' if needed.${RC}"
    fi
}

checkEnv
checkRoot
checkDependencies
installCopilot
