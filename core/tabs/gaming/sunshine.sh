#!/bin/sh -e

. ../common-script.sh

# Sunshine Installation Script
# Installs Sunshine, a self-hosted game streaming server

installSunshine() {
    printf "%b\n" "${YELLOW}Installing Sunshine...${RC}"

    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm sunshine
            ;;
        apt)
            "$ESCALATION_TOOL" apt-get update
            "$ESCALATION_TOOL" apt-get install -y sunshine
            ;;
        dnf)
            "$ESCALATION_TOOL" dnf install -y sunshine
            ;;
        zypper)
            "$ESCALATION_TOOL" zypper install -y sunshine
            ;;
        apk)
            "$ESCALATION_TOOL" apk add sunshine
            ;;
        xbps-install)
            "$ESCALATION_TOOL" xbps-install -Sy sunshine
            ;;
        *)
            printf "%b\n" "${RED}Error: Unsupported package manager. Please install Sunshine manually.${RC}"
            exit 1
            ;;
    esac

    if command_exists sunshine; then
        printf "%b\n" "${GREEN}Sunshine installed successfully.${RC}"
    else
        printf "%b\n" "${RED}Error: Failed to install Sunshine.${RC}"
        exit 1
    fi
}

enableSunshineService() {
    printf "%b\n" "${YELLOW}Enabling Sunshine service...${RC}"

    if command_exists systemctl; then
        "$ESCALATION_TOOL" systemctl enable sunshine
        "$ESCALATION_TOOL" systemctl start sunshine
        printf "%b\n" "${GREEN}Sunshine service enabled and started.${RC}"
    else
        printf "%b\n" "${YELLOW}Note: systemctl not found. Please start Sunshine manually.${RC}"
    fi
}

checkEnv
checkEscalationTool
installSunshine
enableSunshineService

printf "%b\n" "${GREEN}Sunshine installation completed!${RC}"
