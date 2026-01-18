#!/bin/sh -e

. ../common-script.sh

# Deckify Installation Script
# Installs Deckify, a tool for managing Steam Deck configurations

installDeckify() {
    printf "%b\n" "${YELLOW}Installing Deckify...${RC}"

    # Check if curl is available
    if ! command_exists curl; then
        printf "%b\n" "${RED}Error: curl is required but not installed.${RC}"
        exit 1
    fi

    # Download and execute the installation script
    if bash <(curl -sSL https://raw.githubusercontent.com/unlbslk/arch-deckify/refs/heads/main/install.sh); then
        printf "%b\n" "${GREEN}Deckify installed successfully.${RC}"
    else
        printf "%b\n" "${RED}Error: Failed to install Deckify.${RC}"
        exit 1
    fi
}

checkEnv
installDeckify