#!/bin/sh -e

. ../common-script.sh

HARDENING_PROFILE=${HARDENING_PROFILE:-ctt}

ensureFirewalldRunning() {
    if ! command_exists systemctl; then
        return
    fi

    printf "%b\n" "${YELLOW}Ensuring firewalld is enabled and running${RC}"
    "$ESCALATION_TOOL" systemctl enable --now firewalld
}

configureCTTProfile() {
    printf "%b\n" "${YELLOW}Configuring FirewallD with recommended rules${RC}"

    printf "%b\n" "${YELLOW}Setting default zone to public (FirewallD)${RC}"
    "$ESCALATION_TOOL" firewall-cmd --set-default-zone=public

    printf "%b\n" "${YELLOW}Allowing SSH service (FirewallD)${RC}"
    "$ESCALATION_TOOL" firewall-cmd --permanent --add-service=ssh

    printf "%b\n" "${YELLOW}Implementing SSH brute force protection (FirewallD)${RC}"
    "$ESCALATION_TOOL" firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT_direct 0 -p tcp --dport 22 \
        -m state --state NEW -m recent --set
    "$ESCALATION_TOOL" firewall-cmd --permanent --direct --add-rule ipv4 filter INPUT_direct 1 -p tcp --dport 22 \
        -m state --state NEW -m recent --update --seconds 30 --hitcount 6 \
        -j REJECT --reject-with tcp-reset
    "$ESCALATION_TOOL" firewall-cmd --permanent --direct --add-rule ipv6 filter INPUT_direct 0 -p tcp --dport 22 \
        -m state --state NEW -m recent --set
    "$ESCALATION_TOOL" firewall-cmd --permanent --direct --add-rule ipv6 filter INPUT_direct 1 -p tcp --dport 22 \
        -m state --state NEW -m recent --update --seconds 30 --hitcount 6 \
        -j REJECT --reject-with tcp-reset

    printf "%b\n" "${YELLOW}Allowing HTTP service (FirewallD)${RC}"
    "$ESCALATION_TOOL" firewall-cmd --permanent --add-service=http

    printf "%b\n" "${YELLOW}Allowing HTTPS service (FirewallD)${RC}"
    "$ESCALATION_TOOL" firewall-cmd --permanent --add-service=https

    printf "%b\n" "${YELLOW}Reloading FirewallD configuration${RC}"
    "$ESCALATION_TOOL" firewall-cmd --reload

    printf "%b\n" "${GREEN}Enabled FirewallD with Baselines!${RC}"
}

configureDesktopProfile() {
    printf "%b\n" "${YELLOW}Configuring FirewallD with desktop-focused defaults${RC}"

    printf "%b\n" "${YELLOW}Setting default zone to public (FirewallD)${RC}"
    "$ESCALATION_TOOL" firewall-cmd --set-default-zone=public

    if "$ESCALATION_TOOL" firewall-cmd --permanent --query-service=ssh >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Removing SSH service from the default zone${RC}"
        "$ESCALATION_TOOL" firewall-cmd --permanent --remove-service=ssh
    fi

    if "$ESCALATION_TOOL" firewall-cmd --permanent --query-service=http >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Removing HTTP service from the default zone${RC}"
        "$ESCALATION_TOOL" firewall-cmd --permanent --remove-service=http
    fi

    if "$ESCALATION_TOOL" firewall-cmd --permanent --query-service=https >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Removing HTTPS service from the default zone${RC}"
        "$ESCALATION_TOOL" firewall-cmd --permanent --remove-service=https
    fi

    printf "%b\n" "${YELLOW}Reloading FirewallD configuration${RC}"
    "$ESCALATION_TOOL" firewall-cmd --reload

    printf "%b\n" "${GREEN}Enabled desktop firewall defaults${RC}"
    printf "%b\n" "${CYAN}No inbound services were opened automatically. Add only what you intentionally expose.${RC}"
}

configureFirewallD() {
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
ensureFirewalldRunning
configureFirewallD
