#!/bin/sh -e

# CLI Tools Installation Script
# Installs basic command-line utilities for post-system-setup

. ../../common-script.sh

checkEnv

printf "%b\n" "${CYAN}Installing CLI Tools...${RC}"

BASE_PACKAGES="atop bat bluetui bmon btop bzip2 cmake ctop curl diskonaut dnsmasq exa extra-cmake-modules fzf git github-cli glances gotop gpg-tui gping gzip hashcat htop iftop iotop jq just khal kmon lazysql-bin lazydocker lynis micro mtr ncdu netscanner nethogs nmap nvtop php-imagick ripgrep samba sshfs starship stow tar termscp termshark trash-cli ufw ugrep unrar unzip wavemon wget wireguard-tools xz yazi yq yubikey-personalization zoxide zip"

# Map packages using a common base plus small per-distro exception lists
map_packages() {
    case "$PACKAGER" in
        pacman)
            # pcscd daemon is provided by the pcsc-lite package on Arch
            echo "$BASE_PACKAGES networkmanager pcsc-lite fd oryx pamu2f bind nfs-utils gdu gtop lazymake lazyjournal cronboard sshm multranslate searxngr nemu caligula rainfrog systemd-manager-tui"
            ;;
        apt-get|nala)
            echo "$BASE_PACKAGES network-manager pcscd fd-find libpam-u2f gh bind9-dnsutils nfs-common"
            ;;
        dnf)
            echo "$BASE_PACKAGES NetworkManager pcsc-lite fd-find gh bind-utils nfs-utils"
            ;;
        zypper)
            echo "$BASE_PACKAGES NetworkManager pcsc-lite fd gh bind-utils nfs-client"
            ;;
        apk)
            echo "$BASE_PACKAGES networkmanager pcsc-lite fd gh bind-tools nfs-utils"
            ;;
        xbps-install)
            echo "$BASE_PACKAGES NetworkManager pcsc-lite fd gh bind-utils nfs-utils"
            ;;
    esac
}

PACKAGES_TO_INSTALL=$(map_packages)

if [ -z "$PACKAGES_TO_INSTALL" ]; then
    printf "%b\n" "${RED}No packages available for this distribution${RC}"
    exit 1
fi

printf "%b\n" "${CYAN}Installing: $PACKAGES_TO_INSTALL${RC}"

# Idempotent Chaotic AUR setup — only runs the full install if the repo is absent
ensure_chaotic_aur() {
    grep -q "\[chaotic-aur\]" /etc/pacman.conf && return 0
    printf "%b\n" "${YELLOW}Setting up Chaotic AUR repository...${RC}"
    "$ESCALATION_TOOL" pacman-key --recv-key 3056513887B78AEB --keyserver keyserver.ubuntu.com
    "$ESCALATION_TOOL" pacman-key --lsign-key 3056513887B78AEB
    "$ESCALATION_TOOL" pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-keyring.pkg.tar.zst'
    "$ESCALATION_TOOL" pacman -U --noconfirm 'https://cdn-mirror.chaotic.cx/chaotic-aur/chaotic-mirrorlist.pkg.tar.zst'
    printf "\n[chaotic-aur]\nInclude = /etc/pacman.d/chaotic-mirrorlist" | "$ESCALATION_TOOL" tee -a /etc/pacman.conf
    "$ESCALATION_TOOL" pacman -Sy --noconfirm
    printf "%b\n" "${GREEN}Chaotic AUR set up successfully${RC}"
}

# Install packages based on package manager
case "$PACKAGER" in
    pacman)
        # Split packages into repo-available vs extras to enable a single batch
        # transaction for repo packages. This collapses N snapper hook pairs (one
        # per individual install) down to one pair for the whole repo set — a major
        # speedup on systems with snapper/limine post-transaction hooks.
        printf "%b\n" "${YELLOW}Checking package availability...${RC}"
        REPO_PKGS=""
        EXTRA_PKGS=""
        for pkg in $PACKAGES_TO_INSTALL; do
            if pacman -Si "$pkg" >/dev/null 2>&1; then
                REPO_PKGS="$REPO_PKGS $pkg"
            else
                EXTRA_PKGS="$EXTRA_PKGS $pkg"
            fi
        done

        if [ -n "$REPO_PKGS" ]; then
            printf "%b\n" "${YELLOW}Installing official repo packages in one batch...${RC}"
            # shellcheck disable=SC2086
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm $REPO_PKGS || {
                printf "%b\n" "${YELLOW}[!] Batch install failed, falling back to individual installs${RC}"
                for pkg in $REPO_PKGS; do
                    "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm "$pkg" 2>/dev/null || {
                        printf "%b\n" "${YELLOW}[!] Skipping $pkg (conflict or error)${RC}"
                    }
                done
            }
        fi

        CHAOTIC_AUR_READY=false
        for pkg in $EXTRA_PKGS; do
            printf "%b\n" "${YELLOW}[!] $pkg not in official repos, trying AUR...${RC}"
            aur_ok=false
            if [ -n "$AUR_HELPER" ]; then
                "$AUR_HELPER" -S --needed --noconfirm "$pkg" 2>/dev/null && aur_ok=true
            fi
            if [ "$aur_ok" = false ]; then
                printf "%b\n" "${YELLOW}[!] $pkg not in AUR, trying Chaotic AUR...${RC}"
                if [ "$CHAOTIC_AUR_READY" = false ]; then
                    ensure_chaotic_aur
                    CHAOTIC_AUR_READY=true
                fi
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm "$pkg" 2>/dev/null || {
                    printf "%b\n" "${YELLOW}[!] Skipping $pkg (not found in official repos, AUR, or Chaotic AUR)${RC}"
                }
            fi
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