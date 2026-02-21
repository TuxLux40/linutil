#!/bin/sh -e

# CLI Tools Installation Script
# Installs useful command-line utilities for post-system-setup
# Focuses on productivity, security, and development tools

. ../../common-script.sh

checkEnv

printf "%b\n" "${CYAN}Installing CLI Tools...${RC}"

BASE_PACKAGES="aircrack-ng atop bat bluetui bmon btop bzip2 cargo ctop curl diskonaut dnsmasq exa fzf git glances gotop gpg-tui gping grub-customizer gzip hashcat htop iftop iotop john jq just khal kmon lazysql-bin lazydocker lynis micro mtr ncdu netscanner nethogs nmap nmtui nvtop opencode pcscd php-imagick ranger ripgrep samba sshfs starship stow tar tcpdump termscp termshark trash-cli trippy ufw ugrep unrar unzip wavemon wget wireguard-tools xz yazi yq yubikey-personalization zoxide zip"

# Map packages using a common base plus small per-distro exception lists
map_packages() {
    case "$PACKAGER" in
        pacman)
            echo "$BASE_PACKAGES fd oryx pamu2f github-cli bind nfs-utils gdu gtop sockttop kyanos corefreq lazymake ducker glow cronboard sshm gocheat multranslate searxngr distrobox-tui nemu caligula rainfrog systemd-manager-tui"
            ;;
        apt-get|nala)
            echo "$BASE_PACKAGES fd-find libpam-u2f gh bind9-dnsutils nfs-common"
            ;;
        dnf)
            echo "$BASE_PACKAGES fd-find gh bind-utils nfs-utils"
            ;;
        zypper)
            echo "$BASE_PACKAGES fd gh bind-utils nfs-client"
            ;;
        apk)
            echo "$BASE_PACKAGES fd gh bind-tools nfs-utils"
            ;;
        xbps-install)
            echo "$BASE_PACKAGES fd gh bind-utils nfs-utils"
            ;;
    esac
}

PACKAGES_TO_INSTALL=$(map_packages)

if [ -z "$PACKAGES_TO_INSTALL" ]; then
    printf "%b\n" "${RED}No packages available for this distribution${RC}"
    exit 1
fi

printf "%b\n" "${CYAN}Installing: $PACKAGES_TO_INSTALL${RC}"

# Install packages based on package manager
case "$PACKAGER" in
    pacman)
        printf "%b\n" "${YELLOW}Installing from official repositories...${RC}"
        for pkg in $PACKAGES_TO_INSTALL; do
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
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg" 2>/dev/null || {
                printf "%b\n" "${YELLOW}[!] Skipping $pkg (conflict or not available)${RC}"
            }
        done
        ;;
    dnf)
        printf "%b\n" "${YELLOW}Installing from dnf repositories...${RC}"
        for pkg in $PACKAGES_TO_INSTALL; do
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg" 2>/dev/null || {
                printf "%b\n" "${YELLOW}[!] Skipping $pkg (conflict or not available)${RC}"
            }
        done
        ;;
    zypper)
        printf "%b\n" "${YELLOW}Installing from zypper repositories...${RC}"
        for pkg in $PACKAGES_TO_INSTALL; do
            "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg" 2>/dev/null || {
                printf "%b\n" "${YELLOW}[!] Skipping $pkg (conflict or not available)${RC}"
            }
        done
        ;;
    apk)
        printf "%b\n" "${YELLOW}Installing from apk repositories...${RC}"
        for pkg in $PACKAGES_TO_INSTALL; do
            "$ESCALATION_TOOL" "$PACKAGER" add "$pkg" 2>/dev/null || {
                printf "%b\n" "${YELLOW}[!] Skipping $pkg (conflict or not available)${RC}"
            }
        done
        ;;
    xbps-install)
        printf "%b\n" "${YELLOW}Installing from xbps repositories...${RC}"
        for pkg in $PACKAGES_TO_INSTALL; do
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

printf "%b\n" "${GREEN}CLI Tools installation completed!${RC}"