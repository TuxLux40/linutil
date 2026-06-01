#!/bin/sh -e

. ../../common-script.sh

checkRoot() {
    if [ "$(id -u)" -eq 0 ]; then
        printf "%b\n" "${RED}This script should not be run as root!${RC}"
        exit 1
    fi
}

checkDependencies() {
    if ! command_exists uv; then
        printf "%b\n" "${RED}uv is required but not installed.${RC}"
        printf "%b\n" "${YELLOW}Install it via: https://docs.astral.sh/uv/getting-started/installation/${RC}"
        exit 1
    fi
}

installHoncho() {
    if command_exists honcho; then
        printf "%b\n" "${GREEN}Honcho CLI is already installed.${RC}"
        printf "%b" "${YELLOW}Do you want to update Honcho CLI? [y/N] ${RC}"
        read -r update_choice
        case "$update_choice" in
        y | Y)
            printf "%b\n" "${CYAN}Updating Honcho CLI...${RC}"
            uv tool install --upgrade honcho-cli
            printf "%b\n" "${GREEN}Honcho CLI updated successfully.${RC}"
            ;;
        *)
            printf "%b\n" "${CYAN}Skipping update.${RC}"
            ;;
        esac
    else
        printf "%b\n" "${CYAN}Installing Honcho CLI...${RC}"
        uv tool install honcho-cli
        printf "%b\n" "${GREEN}Honcho CLI installed successfully.${RC}"
        printf "%b\n" "${YELLOW}Initialize Honcho with: honcho init${RC}"
        printf "%b\n" "${YELLOW}Verify setup with: honcho doctor${RC}"
    fi
}

checkEnv
checkRoot
checkDependencies
installHoncho
