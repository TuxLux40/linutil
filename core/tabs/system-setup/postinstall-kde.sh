#!/bin/sh -e

# KDE Post-Installation Script
# This script configures a fresh KDE installation with custom settings

. ../common-script.sh

printf "%b\n" "${YELLOW}=== KDE Post-Installation Configuration ===${RC}"
printf "%b\n" "${CYAN}This script will configure:${RC}"
printf "  - Global themes and styles\n"
printf "  - Keyboard shortcuts\n"
printf "  - Window decorations and effects\n"
printf "  - Panel configuration\n"
printf "\n"

# Ask for confirmation
printf "%b\n" "${YELLOW}Do you want to proceed? (y/n)${RC}"
read -r response
case "$response" in
    [yY][eE][sS]|[yY])
        printf "%b\n" "${GREEN}Starting configuration...${RC}"
        ;;
    *)
        printf "%b\n" "${RED}Configuration cancelled.${RC}"
        exit 0
        ;;
esac

# Run global theme setup
printf "%b\n" "${CYAN}Step 1/2: Configuring global themes...${RC}"
if [ -f "./global-theme.sh" ]; then
    sh ./global-theme.sh
else
    printf "%b\n" "${RED}Error: global-theme.sh not found!${RC}"
fi

# Run KDE shortcuts setup
printf "%b\n" "${CYAN}Step 2/2: Configuring KDE shortcuts...${RC}"
if [ -f "./kde-shortcuts.sh" ]; then
    sh ./kde-shortcuts.sh
else
    printf "%b\n" "${RED}Error: kde-shortcuts.sh not found!${RC}"
fi

printf "%b\n" "${GREEN}=== KDE Post-Installation Complete! ===${RC}"
printf "%b\n" "${YELLOW}Please log out and back in to apply all changes.${RC}"
printf "%b\n" "${CYAN}You can run individual scripts again if needed:${RC}"
printf "  - ./global-theme.sh  (themes, icons, decorations)\n"
printf "  - ./kde-shortcuts.sh (keyboard shortcuts)\n"
