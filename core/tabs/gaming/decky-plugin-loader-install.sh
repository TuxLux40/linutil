#!/bin/sh -e

. ../common-script.sh

# Decky Plugin Loader Installation Script
# Installs Decky Loader, a plugin manager for Steam Deck

installDeckyLoader() {
    printf "%b\n" "${YELLOW}Installing Decky Plugin Loader...${RC}"

    # Check if curl is available
    if ! command_exists curl; then
        printf "%b\n" "${RED}Error: curl is required but not installed.${RC}"
        exit 1
    fi

    # Download and execute the installation script
    if bash <(curl -sSL https://raw.githubusercontent.com/unlbslk/arch-deckify/refs/heads/main/setup_deckyloader.sh); then
        printf "%b\n" "${GREEN}Decky Plugin Loader installed successfully.${RC}"
    else
        printf "%b\n" "${RED}Error: Failed to install Decky Plugin Loader.${RC}"
        exit 1
    fi
}

checkEnv
installDeckyLoader