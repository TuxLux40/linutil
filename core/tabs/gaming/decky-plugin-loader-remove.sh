#!/bin/sh -e

. ../common-script.sh

# Decky Plugin Loader Removal Script
# Removes Decky Loader from Steam Deck

removeDeckyLoader() {
    printf "%b\n" "${YELLOW}Removing Decky Plugin Loader...${RC}"

    # Check if curl is available
    if ! command_exists curl; then
        printf "%b\n" "${RED}Error: curl is required but not installed.${RC}"
        exit 1
    fi

    # Download and execute the removal script
    if bash <(curl -sSL https://raw.githubusercontent.com/unlbslk/arch-deckify/refs/heads/main/remove_deckyloader.sh); then
        printf "%b\n" "${GREEN}Decky Plugin Loader removed successfully.${RC}"
    else
        printf "%b\n" "${RED}Error: Failed to remove Decky Plugin Loader.${RC}"
        exit 1
    fi
}

checkEnv
removeDeckyLoader