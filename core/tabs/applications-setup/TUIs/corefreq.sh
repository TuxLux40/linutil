#!/bin/sh -e

. ../../common-script.sh

install_corefreq() {
    printf "%b\n" "${YELLOW}Installing CoreFreq...${RC}"
    
    # Check and install build tools
    checkBuildTools
    
    # Check for git
    if ! command_exists git; then
        printf "%b\n" "${YELLOW}Installing git...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm git
                ;;
            apt-get|nala)
                "$ESCALATION_TOOL" "$PACKAGER" install -y git
                ;;
            dnf)
                "$ESCALATION_TOOL" "$PACKAGER" install -y git
                ;;
            zypper)
                "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install git
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add git
                ;;
            *)
                printf "%b\n" "${RED}git installation not supported for this package manager.${RC}"
                return 1
                ;;
        esac
    fi
    
    # Clone CoreFreq repository
    TEMP_DIR="/tmp/corefreq_build"
    printf "%b\n" "${CYAN}Cloning CoreFreq from GitHub...${RC}"
    
    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi
    
    if ! git clone https://github.com/cyring/CoreFreq.git "$TEMP_DIR"; then
        printf "%b\n" "${RED}Failed to clone CoreFreq repository.${RC}"
        return 1
    fi
    
    cd "$TEMP_DIR"
    
    # Build CoreFreq
    printf "%b\n" "${CYAN}Building CoreFreq...${RC}"
    if make -j "$(nproc)"; then
        printf "%b\n" "${GREEN}Build completed successfully.${RC}"
    else
        printf "%b\n" "${RED}Build failed.${RC}"
        cd /
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Install CoreFreq
    printf "%b\n" "${CYAN}Installing CoreFreq binaries and kernel module...${RC}"
    if "$ESCALATION_TOOL" make install; then
        printf "%b\n" "${GREEN}CoreFreq installed successfully!${RC}"
    else
        printf "%b\n" "${RED}Installation failed.${RC}"
        cd /
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Setup systemd service
    printf "%b\n" "${CYAN}Setting up systemd service...${RC}"
    if [ -f "corefreqd.service" ]; then
        "$ESCALATION_TOOL" install -o root -g root -m 0644 corefreqd.service /etc/systemd/system/corefreqd.service
        "$ESCALATION_TOOL" systemctl daemon-reload
        printf "%b\n" "${GREEN}Systemd service installed.${RC}"
    fi
    
    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
    
    # Verify installation
    if command_exists corefreq-cli && command_exists corefreqd; then
        printf "%b\n" "${GREEN}✓ CoreFreq installation completed!${RC}"
        printf "%b\n" "${CYAN}Usage:${RC}"
        printf "%b\n" "${CYAN}  Load kernel module: sudo modprobe corefreqk${RC}"
        printf "%b\n" "${CYAN}  Start daemon: sudo systemctl start corefreqd${RC}"
        printf "%b\n" "${CYAN}  Start client: corefreq-cli${RC}"
        printf "%b\n" "${CYAN}  Stop daemon: sudo systemctl stop corefreqd${RC}"
        printf "%b\n" "${CYAN}  Unload module: sudo modprobe -r corefreqk${RC}"
        printf "%b\n" "${YELLOW}Note: CoreFreq requires root privileges and CPU monitoring via kernel module.${RC}"
    else
        printf "%b\n" "${RED}Installation verification failed.${RC}"
        return 1
    fi
}

checkEnv
checkEscalationTool
install_corefreq