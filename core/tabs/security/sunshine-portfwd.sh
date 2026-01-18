#!/bin/sh -e

. ../common-script.sh

# Sunshine Port Forwarding Setup Script
# Configures port forwarding for Sunshine game streaming server
# TCP: 47984, 47989, 48010
# UDP: 47998, 47999, 48000, 48002, 48010

configureSunshineUFW() {
    printf "%b\n" "${YELLOW}Configuring Sunshine ports for UFW...${RC}"

    # TCP ports
    "$ESCALATION_TOOL" ufw allow 47984/tcp
    "$ESCALATION_TOOL" ufw allow 47989/tcp
    "$ESCALATION_TOOL" ufw allow 48010/tcp

    # UDP ports
    "$ESCALATION_TOOL" ufw allow 47998/udp
    "$ESCALATION_TOOL" ufw allow 47999/udp
    "$ESCALATION_TOOL" ufw allow 48000/udp
    "$ESCALATION_TOOL" ufw allow 48002/udp
    "$ESCALATION_TOOL" ufw allow 48010/udp

    printf "%b\n" "${GREEN}Sunshine ports configured for UFW${RC}"
}

configureSunshineFirewalld() {
    printf "%b\n" "${YELLOW}Configuring Sunshine ports for FirewallD...${RC}"

    # TCP ports
    "$ESCALATION_TOOL" firewall-cmd --permanent --add-port=47984/tcp
    "$ESCALATION_TOOL" firewall-cmd --permanent --add-port=47989/tcp
    "$ESCALATION_TOOL" firewall-cmd --permanent --add-port=48010/tcp

    # UDP ports
    "$ESCALATION_TOOL" firewall-cmd --permanent --add-port=47998/udp
    "$ESCALATION_TOOL" firewall-cmd --permanent --add-port=47999/udp
    "$ESCALATION_TOOL" firewall-cmd --permanent --add-port=48000/udp
    "$ESCALATION_TOOL" firewall-cmd --permanent --add-port=48002/udp
    "$ESCALATION_TOOL" firewall-cmd --permanent --add-port=48010/udp

    "$ESCALATION_TOOL" firewall-cmd --reload
    printf "%b\n" "${GREEN}Sunshine ports configured for FirewallD${RC}"
}

configureSunshineIPTables() {
    printf "%b\n" "${YELLOW}Configuring Sunshine ports for iptables...${RC}"

    # TCP ports
    "$ESCALATION_TOOL" iptables -A INPUT -p tcp --dport 47984 -j ACCEPT
    "$ESCALATION_TOOL" iptables -A INPUT -p tcp --dport 47989 -j ACCEPT
    "$ESCALATION_TOOL" iptables -A INPUT -p tcp --dport 48010 -j ACCEPT

    # UDP ports
    "$ESCALATION_TOOL" iptables -A INPUT -p udp --dport 47998 -j ACCEPT
    "$ESCALATION_TOOL" iptables -A INPUT -p udp --dport 47999 -j ACCEPT
    "$ESCALATION_TOOL" iptables -A INPUT -p udp --dport 48000 -j ACCEPT
    "$ESCALATION_TOOL" iptables -A INPUT -p udp --dport 48002 -j ACCEPT
    "$ESCALATION_TOOL" iptables -A INPUT -p udp --dport 48010 -j ACCEPT

    printf "%b\n" "${GREEN}Sunshine ports configured for iptables${RC}"
}

detectAndConfigureFirewall() {
    if command_exists ufw; then
        configureSunshineUFW
    elif command_exists firewall-cmd; then
        configureSunshineFirewalld
    elif command_exists iptables; then
        configureSunshineIPTables
    else
        printf "%b\n" "${RED}Error: No supported firewall detected (UFW, FirewallD, or iptables required)${RC}"
        exit 1
    fi
}

checkEnv
checkEscalationTool
detectAndConfigureFirewall

printf "%b\n" "${GREEN}Sunshine port forwarding configuration completed!${RC}"