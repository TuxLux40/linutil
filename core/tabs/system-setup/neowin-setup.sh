#!/bin/sh -e

. ../common-script.sh

install_neowin() {
    if ! command_exists git; then
        printf "%b\n" "${YELLOW}Installing git...${RC}"
        case "$PACKAGER" in
            apt-get | nala)
                "$ESCALATION_TOOL" "$PACKAGER" install -y git
                ;;
            zypper)
                "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install git
                ;;
            dnf | yum)
                "$ESCALATION_TOOL" "$PACKAGER" install -y git
                ;;
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm git
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy git
                ;;
            *)
                printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
                exit 1
                ;;
        esac
    fi

    TEMP_DIR=$(mktemp -d)
    # shellcheck disable=SC2064
    trap "rm -rf '$TEMP_DIR'" EXIT

    printf "%b\n" "${YELLOW}Cloning NeoWin repository...${RC}"
    git clone --depth=1 https://github.com/TuxLux40/NeoWin.git "$TEMP_DIR/NeoWin"

    cd "$TEMP_DIR/NeoWin"
    chmod +x install.sh
    bash install.sh install

    printf "%b\n" "${GREEN}NeoWin KDE theme installed successfully!${RC}"
    printf "%b\n" "${CYAN}Tip: Run './install.sh restore-panel' from the cloned repo to apply the saved panel layout.${RC}"
}

checkEnv
checkEscalationTool
install_neowin
