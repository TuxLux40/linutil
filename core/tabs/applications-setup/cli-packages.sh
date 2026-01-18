#!/bin/sh -e

# CLI Tools Installation Script
# Installs useful command-line utilities for post-system-setup
# Focuses on productivity, security, and development tools

. "$(dirname "$(realpath "$0")")/../common-script.sh"

checkEnv

printf "%b\n" "${CYAN}Installing CLI Tools...${RC}"

# Map packages to distribution-specific names
map_packages() {
    local category=$1
    local packages=""
    
    case "$PACKAGER" in
        pacman)
            case "$category" in
                productivity) packages="bat exa ripgrep fd jq yq just ugrep zoxide trash-cli" ;;
                security) packages="wireguard-tools ufw aircrack-ng hashcat john pcscd pamu2f yubikey-personalization" ;;
                development) packages="git github-cli" ;;
                network) packages="curl wget nmap tcpdump bind mtr" ;;
                compression) packages="zip unzip tar gzip bzip2 xz unrar" ;;
                utilities) packages="htop iotop iftop nethogs dnsmasq samba nfs-utils" ;;
                tui) packages="netscanner nmtui termshark atop bmon btop glances gotop gping ncdu nvtop lazysql lazydocker diskonaut fzf nnn ranger yazi bluetui gpg-tui jrnl khal lnav termscp wavemon" ;;
                all) packages="bat exa ripgrep fd jq yq just ugrep zoxide trash-cli wireguard-tools ufw aircrack-ng hashcat john pcscd pamu2f yubikey-personalization git github-cli curl wget nmap tcpdump bind mtr zip unzip tar gzip bzip2 xz unrar htop iotop iftop nethogs dnsmasq samba nfs-utils netscanner nmtui termshark atop bmon btop glances gotop gping ncdu nvtop lazysql-bin lazydocker diskonaut fzf nnn ranger yazi bluetui gpg-tui jrnl khal lnav termscp wavemon" ;;
            esac
            ;;
        apt-get|nala)
            case "$category" in
                productivity) packages="bat exa ripgrep fd-find jq yq just ugrep zoxide trash-cli" ;;
                security) packages="wireguard-tools ufw aircrack-ng hashcat john pcscd libpam-u2f yubikey-personalization" ;;
                development) packages="git gh" ;;
                network) packages="curl wget nmap tcpdump bind9-dnsutils mtr" ;;
                compression) packages="zip unzip tar gzip bzip2 xz-utils unrar" ;;
                utilities) packages="htop iotop iftop nethogs dnsmasq samba nfs-common" ;;
                tui) packages="netscanner nmtui termshark atop bmon btop glances gotop gping ncdu nvtop lazysql lazydocker diskonaut fzf nnn ranger yazi bluetui gpg-tui jrnl khal lnav termscp wavemon" ;;
                all) packages="bat exa ripgrep fd-find jq yq just ugrep zoxide trash-cli wireguard-tools ufw aircrack-ng hashcat john pcscd libpam-u2f yubikey-personalization git gh curl wget nmap tcpdump bind9-dnsutils mtr zip unzip tar gzip bzip2 xz-utils unrar htop iotop iftop nethogs dnsmasq samba nfs-common netscanner nmtui termshark atop bmon btop glances gotop gping ncdu nvtop lazysql-bin lazydocker diskonaut fzf nnn ranger yazi bluetui gpg-tui jrnl khal lnav termscp wavemon" ;;
            esac
            ;;
        dnf)
            case "$category" in
                productivity) packages="bat exa ripgrep fd-find jq yq just ugrep zoxide trash-cli" ;;
                security) packages="wireguard-tools ufw aircrack-ng hashcat john pcscd pamu2f yubikey-personalization" ;;
                development) packages="git gh" ;;
                network) packages="curl wget nmap tcpdump bind-utils mtr" ;;
                compression) packages="zip unzip tar gzip bzip2 xz unrar" ;;
                utilities) packages="htop iotop iftop nethogs dnsmasq samba nfs-utils" ;;
                tui) packages="netscanner nmtui termshark atop bmon btop glances gotop gping ncdu nvtop lazysql-bin lazydocker diskonaut fzf nnn ranger yazi bluetui gpg-tui jrnl khal lnav termscp wavemon" ;;
                all) packages=\"bat exa ripgrep fd-find jq yq just ugrep zoxide trash-cli wireguard-tools ufw aircrack-ng hashcat john pcscd pamu2f yubikey-personalization git gh curl wget nmap tcpdump bind-utils mtr zip unzip tar gzip bzip2 xz unrar htop iotop iftop nethogs dnsmasq samba nfs-utils netscanner nmtui termshark atop bmon btop glances gotop gping ncdu nvtop lazysql-bin lazydocker diskonaut fzf nnn ranger yazi bluetui gpg-tui jrnl khal lnav termscp wavemon\" ;;
            esac
            ;;
        zypper)
            case "$category" in
                productivity) packages="bat exa ripgrep fd jq yq just ugrep zoxide trash-cli" ;;
                security) packages="wireguard-tools ufw aircrack-ng hashcat john pcscd pamu2f yubikey-personalization" ;;
                development) packages="git gh" ;;
                network) packages="curl wget nmap tcpdump bind-utils mtr" ;;
                compression) packages="zip unzip tar gzip bzip2 xz unrar" ;;
                utilities) packages="htop iotop iftop nethogs dnsmasq samba nfs-client" ;;
                tui) packages="netscanner nmtui termshark atop bmon btop glances gotop gping ncdu nvtop lazysql-bin lazydocker diskonaut fzf nnn ranger yazi bluetui gpg-tui jrnl khal lnav termscp wavemon" ;;
                all) packages=\"bat exa ripgrep fd jq yq just ugrep zoxide trash-cli wireguard-tools ufw aircrack-ng hashcat john pcscd pamu2f yubikey-personalization git gh curl wget nmap tcpdump bind-utils mtr zip unzip tar gzip bzip2 xz unrar htop iotop iftop nethogs dnsmasq samba nfs-client netscanner nmtui termshark atop bmon btop glances gotop gping ncdu nvtop lazysql-bin lazydocker diskonaut fzf nnn ranger yazi bluetui gpg-tui jrnl khal lnav termscp wavemon\" ;;
            esac
            ;;
        apk)
            case "$category" in
                productivity) packages="bat exa ripgrep fd jq yq just ugrep zoxide trash-cli" ;;
                security) packages="wireguard-tools ufw aircrack-ng hashcat john pcscd pamu2f yubikey-personalization" ;;
                development) packages="git" ;;
                network) packages="curl wget nmap tcpdump bind-tools mtr" ;;
                compression) packages="zip unzip tar gzip bzip2 xz unrar" ;;
                utilities) packages="htop iotop iftop nethogs dnsmasq samba nfs-utils" ;;
                tui) packages="netscanner nmtui termshark atop bmon btop glances gotop gping ncdu nvtop lazysql-bin lazydocker diskonaut fzf nnn ranger yazi bluetui gpg-tui jrnl khal lnav termscp wavemon" ;;
                all) packages=\"bat exa ripgrep fd jq yq just ugrep zoxide trash-cli wireguard-tools ufw aircrack-ng hashcat john pcscd pamu2f yubikey-personalization git curl wget nmap tcpdump bind-tools mtr zip unzip tar gzip bzip2 xz unrar htop iotop iftop nethogs dnsmasq samba nfs-utils netscanner nmtui termshark atop bmon btop glances gotop gping ncdu nvtop lazysql-bin lazydocker diskonaut fzf nnn ranger yazi bluetui gpg-tui jrnl khal lnav termscp wavemon\" ;;
            esac
            ;;
        xbps-install)
            case "$category" in
                productivity) packages="bat exa ripgrep fd jq yq just ugrep zoxide trash-cli" ;;
                security) packages="wireguard-tools ufw aircrack-ng hashcat john pcscd pamu2f yubikey-personalization" ;;
                development) packages="git gh" ;;
                network) packages="curl wget nmap tcpdump bind-utils mtr" ;;
                compression) packages="zip unzip tar gzip bzip2 xz unrar" ;;
                utilities) packages="htop iotop iftop nethogs dnsmasq samba nfs-utils" ;;
                tui) packages="netscanner nmtui termshark atop bmon btop glances gotop gping ncdu nvtop lazysql-bin lazydocker diskonaut fzf nnn ranger yazi bluetui gpg-tui jrnl khal lnav termscp wavemon" ;;
                all) packages=\"bat exa ripgrep fd jq yq just ugrep zoxide trash-cli wireguard-tools ufw aircrack-ng hashcat john pcscd pamu2f yubikey-personalization git gh curl wget nmap tcpdump bind-utils mtr zip unzip tar gzip bzip2 xz unrar htop iotop iftop nethogs dnsmasq samba nfs-utils netscanner nmtui termshark atop bmon btop glances gotop gping ncdu nvtop lazysql-bin lazydocker diskonaut fzf nnn ranger yazi bluetui gpg-tui jrnl khal lnav termscp wavemon\" ;;
            esac
            ;;
    esac
    
    echo "$packages"
}

printf "%b\n" "${YELLOW}Available CLI Tool Categories:${RC}"
printf "%b\n" "  1) Productivity Tools (bat, exa, ripgrep, fd, jq, yq, just, ugrep, zoxide, trash-cli)"
printf "%b\n" "  2) Security Tools (wireguard-tools, ufw, aircrack-ng, hashcat, john, pcscd, pamu2f, yubikey-personalization)"
printf "%b\n" "  3) Development Tools (git, github-cli)"
printf "%b\n" "  4) Network Tools (curl, wget, nmap, tcpdump, bind-tools, mtr)"
printf "%b\n" "  5) Compression Tools (zip, unzip, tar, gzip, bzip2, xz, unrar)"
printf "%b\n" "  6) System Utilities (htop, iotop, iftop, nethogs, dnsmasq, samba, nfs-utils)"
printf "%b\n" "  7) TUI Tools (netscanner, nmtui, termshark, atop, bmon, btop, glances, gotop, gping, ncdu, nvtop, lazysql-bin, lazydocker, diskonaut, fzf, nnn, ranger, yazi, bluetui, gpg-tui, jrnl, khal, lnav, termscp, wavemon)"
printf "%b\n" "  8) Install All"
printf "%b\n"

read -p "Select option (1-8): " SELECTION

case "$SELECTION" in
    1) CATEGORY="productivity" ;;
    2) CATEGORY="security" ;;
    3) CATEGORY="development" ;;
    4) CATEGORY="network" ;;
    5) CATEGORY="compression" ;;
    6) CATEGORY="utilities" ;;
    7) CATEGORY="tui" ;;
    8) CATEGORY="all" ;;
    *)
        printf "%b\n" "${RED}Invalid selection${RC}"
        exit 1
        ;;
esac

PACKAGES_TO_INSTALL=$(map_packages "$CATEGORY")

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