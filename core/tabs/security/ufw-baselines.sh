#!/bin/sh -e

. ../common-script.sh

HARDENING_PROFILE=${HARDENING_PROFILE:-ctt}

installPkg() {
    if ! command_exists ufw; then
     printf "%b\n" "${YELLOW}Installing UFW...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm ufw
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add ufw
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy ufw
                ;;
            *)
                "$ESCALATION_TOOL" "$PACKAGER" install -y ufw
                ;;
        esac
    else
        printf "%b\n" "${GREEN}UFW is already installed${RC}"
    fi
}

configureCTTProfile() {
    printf "%b\n" "${YELLOW}Using Chris Titus Recommended Firewall Rules${RC}"

    printf "%b\n" "${YELLOW}Disabling UFW${RC}"
    "$ESCALATION_TOOL" ufw --force disable

    printf "%b\n" "${YELLOW}Limiting port 22/tcp (UFW)${RC}"
    "$ESCALATION_TOOL" ufw limit 22/tcp

    printf "%b\n" "${YELLOW}Allowing port 80/tcp (UFW)${RC}"
    "$ESCALATION_TOOL" ufw allow 80/tcp

    printf "%b\n" "${YELLOW}Allowing port 443/tcp (UFW)${RC}"
    "$ESCALATION_TOOL" ufw allow 443/tcp

    printf "%b\n" "${YELLOW}Denying Incoming Packets by Default(UFW)${RC}"
    "$ESCALATION_TOOL" ufw default deny incoming

    printf "%b\n" "${YELLOW}Allowing Outcoming Packets by Default(UFW)${RC}"
    "$ESCALATION_TOOL" ufw default allow outgoing

    "$ESCALATION_TOOL" ufw enable
    printf "%b\n" "${GREEN}Enabled Firewall with Baselines!${RC}"
}

configureDesktopProfile() {
    printf "%b\n" "${YELLOW}Using desktop-focused firewall defaults${RC}"

    printf "%b\n" "${YELLOW}Disabling UFW${RC}"
    "$ESCALATION_TOOL" ufw --force disable

    printf "%b\n" "${YELLOW}Setting logging to medium${RC}"
    "$ESCALATION_TOOL" ufw logging medium

    printf "%b\n" "${YELLOW}Denying incoming packets by default (UFW)${RC}"
    "$ESCALATION_TOOL" ufw default deny incoming

    printf "%b\n" "${YELLOW}Denying routed packets by default (UFW)${RC}"
    "$ESCALATION_TOOL" ufw default deny routed

    printf "%b\n" "${YELLOW}Allowing outgoing packets by default (UFW)${RC}"
    "$ESCALATION_TOOL" ufw default allow outgoing

    "$ESCALATION_TOOL" ufw --force enable
    printf "%b\n" "${GREEN}Enabled desktop firewall defaults${RC}"
    printf "%b\n" "${CYAN}No inbound services were opened automatically. Add only what you intentionally expose.${RC}"
}

configureUFW() {
    case "$HARDENING_PROFILE" in
        desktop)
            configureDesktopProfile
            ;;
        *)
            configureCTTProfile
            ;;
    esac
}

checkEnv
checkEscalationTool
installPkg
configureUFW
