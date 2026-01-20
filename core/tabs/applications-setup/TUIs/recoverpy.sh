#!/bin/sh -e

. ../../common-script.sh

install_recoverpy() {
    printf "%b\n" "${YELLOW}Installing RecoverPy...${RC}"
    
    # Check and install Python3
    checkPython
    
    # Install pip/pipx
    printf "%b\n" "${CYAN}Checking for pip and pipx...${RC}"
    if ! command_exists pip3; then
        printf "%b\n" "${YELLOW}pip3 not found, installing pip3...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm python-pip
                ;;
            apt-get|nala)
                "$ESCALATION_TOOL" "$PACKAGER" install -y python3-pip
                ;;
            dnf)
                "$ESCALATION_TOOL" "$PACKAGER" install -y python3-pip
                ;;
            zypper)
                "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install python3-pip
                ;;
            *)
                printf "%b\n" "${RED}pip3 installation not supported for this package manager.${RC}"
                return 1
                ;;
        esac
    fi
    
    # Install required system tools
    printf "%b\n" "${CYAN}Installing required system tools (grep, coreutils, util-linux, progress)...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm grep coreutils util-linux progress
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y grep coreutils util-linux progress
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" install -y grep coreutils util-linux progress
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install grep coreutils util-linux progress
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add grep coreutils util-linux
            ;;
        *)
            printf "%b\n" "${YELLOW}System tools installation may not be supported for this package manager.${RC}"
            ;;
    esac
    
    # Install RecoverPy using pip
    printf "%b\n" "${CYAN}Installing RecoverPy via pip...${RC}"
    if "$ESCALATION_TOOL" python3 -m pip install recoverpy; then
        printf "%b\n" "${GREEN}RecoverPy installed successfully!${RC}"
    else
        printf "%b\n" "${RED}Failed to install RecoverPy via pip.${RC}"
        return 1
    fi
    
    # Verify installation
    if command_exists recoverpy; then
        printf "%b\n" "${GREEN}✓ RecoverPy installation completed!${RC}"
        printf "%b\n" "${CYAN}Usage:${RC}"
        printf "%b\n" "${CYAN}  sudo recoverpy${RC}"
        printf "%b\n" "${YELLOW}Note: RecoverPy requires root privileges to scan partitions.${RC}"
    else
        printf "%b\n" "${RED}Installation verification failed.${RC}"
        return 1
    fi
}

checkEnv
checkEscalationTool
install_recoverpy