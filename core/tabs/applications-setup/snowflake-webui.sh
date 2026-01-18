#!/bin/sh -e

# Snowflake Relay Web UI Installation Script
# Installs and configures Snowflake anti-censorship proxy with Web UI and system tray integration
# This script clones and runs the setup script from the snowflake-webui repository

. ../common-script.sh

checkEnv

# Check root privileges
checkRoot() {
    if [ "$(id -u)" -ne 0 ]; then
        printf "%b\n" "${RED}This script must be run as root!${RC}"
        exit 1
    fi
}

# Check system
checkSystem() {
    printf "%b\n" "${CYAN}Checking system requirements...${RC}"

    # Check if running on Arch Linux or compatible
    if ! grep -qi "arch\|archarm\|manjaro\|endeavouros" /etc/os-release 2>/dev/null; then
        printf "%b\n" "${YELLOW}This script is optimized for Arch Linux or compatible systems${RC}"
        printf "%b" "${CYAN}Continue anyway? [y/N] ${RC}"
        read -r continue_anyway
        if [ "$continue_anyway" != "y" ] && [ "$continue_anyway" != "Y" ]; then
            exit 1
        fi
    fi

    # Check dependencies
    printf "%b\n" "${CYAN}Checking required tools...${RC}"

    if ! command_exists git; then
        printf "%b\n" "${RED}Git is not installed!${RC}"
        printf "%b\n" "${CYAN}Install Git: sudo pacman -S git${RC}"
        exit 1
    fi
    printf "%b\n" "${GREEN}Git is installed: $(git --version | cut -d' ' -f3)${RC}"

    if ! command_exists curl; then
        printf "%b\n" "${RED}curl is not installed!${RC}"
        printf "%b\n" "${CYAN}Install curl: sudo pacman -S curl${RC}"
        exit 1
    fi
    printf "%b\n" "${GREEN}curl is installed${RC}"

    if ! command_exists bash; then
        printf "%b\n" "${RED}Bash is not installed!${RC}"
        exit 1
    fi
    printf "%b\n" "${GREEN}Bash is installed: $(bash --version | head -n1)${RC}"
}

# Clone repository
cloneRepository() {
    printf "%b\n" "${CYAN}Cloning snowflake-webui repository...${RC}"

    # Use temporary directory for cloning
    TEMP_DIR="/tmp/snowflake-webui-setup-$$"
    mkdir -p "$TEMP_DIR"

    cd "$TEMP_DIR"

    if git clone https://github.com/TuxLux40/snowflake-webui.git; then
        printf "%b\n" "${GREEN}Repository cloned successfully${RC}"
    else
        printf "%b\n" "${RED}Failed to clone repository${RC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    REPO_DIR="$TEMP_DIR/snowflake-webui"
}

# Run setup script
runSetupScript() {
    printf "%b\n" "${CYAN}Running snowflake-webui setup script...${RC}"

    if [ ! -f "$REPO_DIR/snowflake-relay-setup.sh" ]; then
        printf "%b\n" "${RED}Setup script not found in repository!${RC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi

    # Make setup script executable and run it
    chmod +x "$REPO_DIR/snowflake-relay-setup.sh"

    cd "$REPO_DIR"

    # Run the official setup script
    if bash snowflake-relay-setup.sh; then
        printf "%b\n" "${GREEN}Snowflake setup completed successfully!${RC}"
    else
        printf "%b\n" "${RED}Snowflake setup failed!${RC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
}

# Verify installation
verifyInstallation() {
    printf "%b\n" "${CYAN}Verifying Snowflake installation...${RC}"

    # Check if snowflake service exists
    if systemctl list-unit-files | grep -q snowflake.service; then
        printf "%b\n" "${GREEN}Snowflake service is installed${RC}"
    else
        printf "%b\n" "${YELLOW}Snowflake service not found${RC}"
    fi

    # Check if snowflake-webui service exists
    if systemctl list-unit-files | grep -q snowflake-webui.service; then
        printf "%b\n" "${GREEN}Snowflake Web UI service is installed${RC}"
    else
        printf "%b\n" "${YELLOW}Snowflake Web UI service not found${RC}"
    fi

    # Check if snowflake user exists
    if id -u snowflake >/dev/null 2>&1; then
        printf "%b\n" "${GREEN}Snowflake user is created${RC}"
    else
        printf "%b\n" "${YELLOW}Snowflake user not found${RC}"
    fi
}

# Cleanup
cleanup() {
    printf "%b\n" "${CYAN}Cleaning up temporary files...${RC}"
    if [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
        printf "%b\n" "${GREEN}Temporary files removed${RC}"
    fi
}

# Start services
startServices() {
    printf "%b\n" "${CYAN}Starting Snowflake services...${RC}"

    printf "%b" "${GREEN}Start Snowflake proxy service? [y/N] ${RC}"
    read -r start_proxy
    if [ "$start_proxy" = "y" ] || [ "$start_proxy" = "Y" ]; then
        if systemctl start snowflake && systemctl enable snowflake; then
            printf "%b\n" "${GREEN}Snowflake proxy service started and enabled${RC}"
        else
            printf "%b\n" "${RED}Failed to start Snowflake proxy service${RC}"
        fi
    fi

    printf "%b" "${GREEN}Start Snowflake Web UI service? [y/N] ${RC}"
    read -r start_webui
    if [ "$start_webui" = "y" ] || [ "$start_webui" = "Y" ]; then
        if systemctl start snowflake-webui && systemctl enable snowflake-webui; then
            printf "%b\n" "${GREEN}Snowflake Web UI service started and enabled${RC}"
        else
            printf "%b\n" "${RED}Failed to start Snowflake Web UI service${RC}"
        fi
    fi
}

# Print post-installation info
postInstallInfo() {
    printf "%b\n" "${CYAN}${BOLD}=== Snowflake Relay Installation Complete ===${RC}"
    printf "%b\n" ""
    printf "%b\n" "${GREEN}Installation Summary:${RC}"
    printf "%b\n" "  • Snowflake proxy: Anti-censorship relay (Port 8888)"
    printf "%b\n" "  • Web UI Dashboard: Cyberpunk-themed monitoring (Port 9090)"
    printf "%b\n" "  • System Tray: Real-time status monitoring"
    printf "%b\n" "  • Auto-updates: Weekly updates via systemd timer"
    printf "%b\n" ""
    printf "%b\n" "${CYAN}Next Steps:${RC}"
    printf "%b\n" "  1. Enable and start services:"
    printf "%b\n" "     ${YELLOW}sudo systemctl enable snowflake snowflake-webui${RC}"
    printf "%b\n" "     ${YELLOW}sudo systemctl start snowflake snowflake-webui${RC}"
    printf "%b\n" ""
    printf "%b\n" "  2. Access the Web UI:"
    printf "%b\n" "     ${YELLOW}http://localhost:9090${RC}"
    printf "%b\n" ""
    printf "%b\n" "  3. Monitor with system tray:"
    printf "%b\n" "     ${YELLOW}python3 /home/snowflake/snowflake-relay-tray.py${RC}"
    printf "%b\n" ""
    printf "%b\n" "  4. View logs:"
    printf "%b\n" "     ${YELLOW}journalctl -u snowflake -f${RC}"
    printf "%b\n" "     ${YELLOW}journalctl -u snowflake-webui -f${RC}"
    printf "%b\n" ""
    printf "%b\n" "${YELLOW}⚠️  DISCLAIMER:${RC}"
    printf "%b\n" "  This is an UNOFFICIAL Snowflake wrapper, not affiliated with the Tor Project."
    printf "%b\n" "  Use at your own risk. For official Snowflake setup, visit:"
    printf "%b\n" "  ${CYAN}https://snowflake.torproject.org/${RC}"
    printf "%b\n" ""
}

# Main installation flow
main() {
    printf "%b\n" "${CYAN}${BOLD}=== Snowflake Relay Web UI Installer ===${RC}"
    printf "%b\n" ""

    checkRoot
    checkSystem
    cloneRepository
    runSetupScript
    verifyInstallation
    cleanup
    startServices
    postInstallInfo

    printf "%b\n" "${GREEN}✓ Installation completed successfully!${RC}"
}

main
