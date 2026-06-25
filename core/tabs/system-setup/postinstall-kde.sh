#!/bin/sh -e

# KDE Post-Installation Script
# This script configures a fresh KDE installation with my custom settings

. ../common-script.sh

KDE_PACKAGES="ffmpegthumbs audiocd-kio icoutils kdesdk-thumbnailers kdesdk-kio libappimage qt6-imageformats kimageformats taglib resvg kompare kio-admin plymouth-kcm klog"

install_kde_packages() {
    printf "%b\n" "${YELLOW}Installing KDE packages...${RC}"
    case "$PACKAGER" in
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" install -y $KDE_PACKAGES || true
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install $KDE_PACKAGES || true
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" install -y $KDE_PACKAGES || true
            ;;
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm $KDE_PACKAGES || true
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy $KDE_PACKAGES || true
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            exit 1
            ;;
    esac
}

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

# Install KDE packages
printf "%b\n" "${CYAN}Step 1/3: Installing KDE packages...${RC}"
install_kde_packages

# Install NeoWin theme
printf "%b\n" "${CYAN}Step 2/3: Installing NeoWin theme...${RC}"
tmp_neowin=$(mktemp -d)
git clone --depth=1 https://github.com/TuxLux40/NeoWin "$tmp_neowin"
bash "$tmp_neowin/install.sh" install
rm -rf "$tmp_neowin"

# Run KDE shortcuts setup
printf "%b\n" "${CYAN}Step 3/3: Configuring KDE shortcuts...${RC}"
if [ -f "./kde-shortcuts.sh" ]; then
    sh ./kde-shortcuts.sh
else
    printf "%b\n" "${RED}Error: kde-shortcuts.sh not found!${RC}"
fi

printf "%b\n" "${GREEN}=== KDE Post-Installation Complete! ===${RC}"
printf "%b\n" "${YELLOW}Please log out and back in to apply all changes.${RC}"
printf "%b\n" "${CYAN}You can run individual scripts again if needed:${RC}"
printf "  - ./kde-shortcuts.sh (keyboard shortcuts)\n"
