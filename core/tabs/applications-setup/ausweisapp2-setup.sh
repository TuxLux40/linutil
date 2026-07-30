#!/bin/sh -e

. ../common-script.sh

installAusweisApp2() {
    if ! command_exists AusweisApp; then
        printf "%b\n" "${YELLOW}Installing AusweisApp2...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm ausweisapp
                ;;
            apt-get|nala)
                "$ESCALATION_TOOL" "$PACKAGER" install -y ausweisapp2
                ;;
            dnf)
                "$ESCALATION_TOOL" "$PACKAGER" install -y ausweisapp2
                ;;
            zypper)
                "$ESCALATION_TOOL" "$PACKAGER" install -y AusweisApp2
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add ausweisapp2
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy ausweisapp2
                ;;
            *)
                printf "%b\n" "${RED}Package manager not supported for AusweisApp2. Install manually.${RC}"
                return 1
                ;;
        esac
        printf "%b\n" "${GREEN}AusweisApp2 installed successfully.${RC}"
    else
        printf "%b\n" "${GREEN}AusweisApp2 is already installed.${RC}"
    fi
}

installUfw() {
    if ! command_exists ufw; then
        printf "%b\n" "${YELLOW}Installing UFW firewall...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm ufw
                ;;
            apt-get|nala)
                "$ESCALATION_TOOL" "$PACKAGER" install -y ufw
                ;;
            dnf)
                "$ESCALATION_TOOL" "$PACKAGER" install -y ufw
                ;;
            zypper)
                "$ESCALATION_TOOL" "$PACKAGER" install -y ufw
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add ufw
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy ufw
                ;;
            *)
                printf "%b\n" "${RED}Package manager not supported for UFW. Install manually.${RC}"
                return 1
                ;;
        esac
        printf "%b\n" "${GREEN}UFW installed successfully.${RC}"
    else
        printf "%b\n" "${GREEN}UFW is already installed.${RC}"
    fi
}

configureUfw() {
    printf "%b\n" "${YELLOW}Configuring UFW firewall for AusweisApp2...${RC}"
    
    # Enable UFW if not already active
    if ! ufw status | grep -q "Status: active"; then
        printf "%b\n" "${YELLOW}Enabling UFW...${RC}"
        "$ESCALATION_TOOL" ufw --force enable
        printf "%b\n" "${GREEN}UFW enabled.${RC}"
    fi
    
    # Add rule for AusweisApp2 UDP port 24727
    if ! ufw status | grep -q "24727/udp"; then
        printf "%b\n" "${YELLOW}Adding firewall rule for UDP port 24727...${RC}"
        "$ESCALATION_TOOL" ufw allow 24727/udp
        "$ESCALATION_TOOL" ufw reload
        printf "%b\n" "${GREEN}Firewall rule added for port 24727/udp.${RC}"
    else
        printf "%b\n" "${GREEN}Firewall rule for port 24727/udp already exists.${RC}"
    fi
    
    # Display current status
    printf "%b\n" "${YELLOW}Current UFW status:${RC}"
    ufw status verbose
}

checkEnv
installUfw
installAusweisApp2
configureUfw

printf "%b\n" "${GREEN}AusweisApp2 setup complete.${RC}"
printf "%b\n" "To use smartphone as NFC reader: Enable 'Smartphone as card reader' in both apps and scan the QR code.${RC}"
