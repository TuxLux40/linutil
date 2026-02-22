#!/bin/sh -e

# GUI Applications Installation Script
# Installs graphical desktop applications from official repos and AUR

. ../../common-script.sh

checkEnv

printf "%b\n" "${CYAN}Installing GUI Applications...${RC}"

# Base GUI packages available across distributions
# Add new packages here as needed, but only when having the same name across distros
BASE_PACKAGES="gimp gramps libreoffice-fresh obs-studio calibre vlc filezilla ghostty signal-desktop kde-connect kleopatra zed podman-desktop"

# Packages preferred to install from Flathub (to avoid dependency conflicts)
FLATPAK_PREFERRED="clamui cohesion journald-browser gearlever"

# Check if flatpak is available, try to install if not
. ../setup-flatpak.sh

# Map packages using a common base plus per-distro specific packages
map_packages() {
    case "$PACKAGER" in
        pacman)
            echo "$BASE_PACKAGES vlc-plugins-extra yubikey-personalization-gui gnupg-logviewer lact qemu-emulators-full octopi proton-mail-bin proton-pass google-chrome microsoft-edge-stable-bin"
            ;;
        apt-get|nala)
            echo "$BASE_PACKAGES qemu-emulators-full vlc-plugin-base vlc-plugin-qt vlc-plugin-skins2"
            ;;
        dnf)
            echo "$BASE_PACKAGES qemu-emulators-full vlc-core"
            ;;
        zypper)
            echo "$BASE_PACKAGES"
            ;;
        apk)
            echo "$BASE_PACKAGES"
            ;;
        xbps-install)
            echo "$BASE_PACKAGES"
            ;;
    esac
}

PACKAGES_TO_INSTALL=$(map_packages)

if [ -z "$PACKAGES_TO_INSTALL" ]; then
    printf "%b\n" "${RED}No packages available for this distribution${RC}"
    exit 1
fi

printf "%b\n" "${CYAN}Installing: $PACKAGES_TO_INSTALL${RC}"

# Function to install package with Flatpak fallback
install_with_fallback() {
    local pkg="$1"
    local pkg_manager="$2"
    local escalation="$3"
    
    # Check if this package is preferred for Flatpak
    local use_flatpak=0
    for flatpak_pkg in $FLATPAK_PREFERRED; do
        if [ "$pkg" = "$flatpak_pkg" ]; then
            use_flatpak=1
            break
        fi
    done
    
    # Try Flatpak first if preferred
    if [ "$use_flatpak" -eq 1 ]; then
        if command -v flatpak >/dev/null 2>&1; then
            flatpak install -y --noninteractive flathub "$pkg" 2>/dev/null && {
                printf "%b\n" "${GREEN}[✓] Installed $pkg from Flathub${RC}"
                return 0
            }
        fi
    fi
    
    # Continue with regular installation
    return 1
}

# Ensure Flatpak is available if needed
if [ -n "$FLATPAK_PREFERRED" ]; then
    check_flatpak
fi

# Install packages based on package manager
case "$PACKAGER" in
    pacman)
        printf "%b\n" "${YELLOW}Installing from official repositories...${RC}"
        for pkg in $PACKAGES_TO_INSTALL; do
            install_with_fallback "$pkg" "$PACKAGER" "$ESCALATION_TOOL" && continue
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm "$pkg" 2>/dev/null || {
                printf "%b\n" "${YELLOW}[!] Skipping $pkg (not found in official repos)${RC}"
                if [ -n "$AUR_HELPER" ]; then
                    "$AUR_HELPER" -S --needed --noconfirm "$pkg" 2>/dev/null || {
                        printf "%b\n" "${YELLOW}[!] Skipping $pkg (not found in AUR either)${RC}"
                    }
                fi
            }
        done
        ;;
    apt-get|nala)
        printf "%b\n" "${YELLOW}Installing from apt repositories...${RC}"
        "$ESCALATION_TOOL" "$PACKAGER" update
        for pkg in $PACKAGES_TO_INSTALL; do
            install_with_fallback "$pkg" "$PACKAGER" "$ESCALATION_TOOL" && continue
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg" 2>/dev/null || {
                printf "%b\n" "${YELLOW}[!] Skipping $pkg (conflict or not available)${RC}"
            }
        done
        ;;
    dnf)
        printf "%b\n" "${YELLOW}Installing from dnf repositories...${RC}"
        for pkg in $PACKAGES_TO_INSTALL; do
            install_with_fallback "$pkg" "$PACKAGER" "$ESCALATION_TOOL" && continue
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg" 2>/dev/null || {
                printf "%b\n" "${YELLOW}[!] Skipping $pkg (conflict or not available)${RC}"
            }
        done
        ;;
    zypper)
        printf "%b\n" "${YELLOW}Installing from zypper repositories...${RC}"
        for pkg in $PACKAGES_TO_INSTALL; do
            install_with_fallback "$pkg" "$PACKAGER" "$ESCALATION_TOOL" && continue
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg" 2>/dev/null || {
                printf "%b\n" "${YELLOW}[!] Skipping $pkg (conflict or not available)${RC}"
            }
        done
        ;;
    apk)
        printf "%b\n" "${YELLOW}Installing from apk repositories...${RC}"
        for pkg in $PACKAGES_TO_INSTALL; do
            install_with_fallback "$pkg" "$PACKAGER" "$ESCALATION_TOOL" && continue
            "$ESCALATION_TOOL" "$PACKAGER" add "$pkg" 2>/dev/null || {
                printf "%b\n" "${YELLOW}[!] Skipping $pkg (conflict or not available)${RC}"
            }
        done
        ;;
    xbps-install)
        printf "%b\n" "${YELLOW}Installing from xbps repositories...${RC}"
        for pkg in $PACKAGES_TO_INSTALL; do
            install_with_fallback "$pkg" "$PACKAGER" "$ESCALATION_TOOL" && continue
            "$ESCALATION_TOOL" "$PACKAGER" -S "$pkg" 2>/dev/null || {
                printf "%b\n" "${YELLOW}[!] Skipping $pkg (conflict or not available)${RC}"
            }
        done
        ;;
    *)
        printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
        exit 1
        ;;
esac

printf "%b\n" "${GREEN}GUI applications installation completed!${RC}"
