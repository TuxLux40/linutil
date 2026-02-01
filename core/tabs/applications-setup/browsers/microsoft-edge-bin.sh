#!/bin/sh -e

. ../../common-script.sh

installEdge() {
    if command_exists microsoft-edge-stable; then
        printf "%b\n" "${GREEN}Microsoft Edge is already installed.${RC}"
        return
    fi

    printf "%b\n" "${YELLOW}Installing Microsoft Edge (stable)...${RC}"

    case "$PACKAGER" in
        apt-get|nala)
            # Prepare keyring directory
            "$ESCALATION_TOOL" mkdir -p /etc/apt/keyrings
            curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | gpg --dearmor | "$ESCALATION_TOOL" tee /etc/apt/keyrings/microsoft.gpg >/dev/null
            "$ESCALATION_TOOL" chmod 644 /etc/apt/keyrings/microsoft.gpg
            # Add repo
            echo "deb [arch=amd64,arm64,armhf signed-by=/etc/apt/keyrings/microsoft.gpg] https://packages.microsoft.com/repos/edge stable main" | "$ESCALATION_TOOL" tee /etc/apt/sources.list.d/microsoft-edge.list >/dev/null
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y microsoft-edge-stable
            ;;
        dnf)
            curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | "$ESCALATION_TOOL" rpm --import -
            cat << 'EOF' | "$ESCALATION_TOOL" tee /etc/yum.repos.d/microsoft-edge.repo >/dev/null
[microsoft-edge]
name=Microsoft Edge
baseurl=https://packages.microsoft.com/yumrepos/edge
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
            "$ESCALATION_TOOL" "$PACKAGER" install -y microsoft-edge-stable
            ;;
        zypper)
            curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | "$ESCALATION_TOOL" rpm --import -
            cat << 'EOF' | "$ESCALATION_TOOL" tee /etc/zypp/repos.d/microsoft-edge.repo >/dev/null
[microsoft-edge]
name=Microsoft Edge
baseurl=https://packages.microsoft.com/yumrepos/edge
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
            "$ESCALATION_TOOL" "$PACKAGER" refresh
            "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install microsoft-edge-stable
            ;;
        pacman)
            "$AUR_HELPER" -S --needed --noconfirm microsoft-edge-stable-bin
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            exit 1
            ;;
    esac

    printf "%b\n" "${GREEN}Microsoft Edge installed successfully.${RC}"
}

checkEnv
checkEscalationTool
checkAURHelper
installEdge
