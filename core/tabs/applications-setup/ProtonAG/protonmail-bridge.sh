#!/bin/sh -e

. ../../common-script.sh

APP_NAME="Proton Mail Bridge"

add_repo_deb() {
    "$ESCALATION_TOOL" mkdir -p /etc/apt/keyrings
    curl -fsSL https://proton.me/download/bridge/bridge-public-key.asc | gpg --dearmor | "$ESCALATION_TOOL" tee /etc/apt/keyrings/proton-bridge.gpg >/dev/null
    "$ESCALATION_TOOL" chmod 644 /etc/apt/keyrings/proton-bridge.gpg
    echo "deb [signed-by=/etc/apt/keyrings/proton-bridge.gpg] https://repo.protonvpn.com/debian stable main" | "$ESCALATION_TOOL" tee /etc/apt/sources.list.d/proton-bridge.list >/dev/null
    "$ESCALATION_TOOL" "$PACKAGER" update
}

add_repo_rpm() {
    curl -fsSL https://proton.me/download/bridge/bridge-public-key.asc | "$ESCALATION_TOOL" rpm --import -
    cat << 'EOF' | "$ESCALATION_TOOL" tee /etc/yum.repos.d/proton-bridge.repo >/dev/null
[proton-bridge]
name=Proton Mail Bridge
baseurl=https://repo.protonvpn.com/fedora/
enabled=1
gpgcheck=1
gpgkey=https://proton.me/download/bridge/bridge-public-key.asc
EOF
}

install_bridge() {
    case "$PACKAGER" in
        apt-get|nala)
            add_repo_deb
            "$ESCALATION_TOOL" "$PACKAGER" install -y protonmail-bridge
            ;;
        dnf)
            add_repo_rpm
            "$ESCALATION_TOOL" "$PACKAGER" install -y protonmail-bridge
            ;;
        zypper)
            add_repo_rpm
            "$ESCALATION_TOOL" "$PACKAGER" refresh
            "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install protonmail-bridge
            ;;
        pacman)
            if [ -n "$AUR_HELPER" ]; then
                "$AUR_HELPER" -S --needed --noconfirm protonmail-bridge
            else
                printf "%b\n" "${RED}AUR helper not found. Please install protonmail-bridge using your AUR tool.${RC}"
                return 1
            fi
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            return 1
            ;;
    esac
    return 0
}

main() {
    if command_exists protonmail-bridge; then
        printf "%b\n" "${GREEN}${APP_NAME} is already installed.${RC}"
        exit 0
    fi

    checkEnv
    checkEscalationTool
    checkAURHelper

    printf "%b\n" "${YELLOW}Installing ${APP_NAME}...${RC}"
    if install_bridge; then
        printf "%b\n" "${GREEN}${APP_NAME} installation completed.${RC}"
    else
        printf "%b\n" "${RED}Installation failed. Please check the Proton Bridge download page.${RC}"
        exit 1
    fi
}

main
