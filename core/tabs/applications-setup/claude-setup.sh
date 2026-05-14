
#!/bin/sh -e

. ../common-script.sh

checkRoot() {
    if [ "$(id -u)" -eq 0 ]; then
        printf "%b\n" "${RED}This script should not be run as root!${RC}"
        exit 1
    fi
}

installClaude() {
    if command_exists claude; then
        printf "%b\n" "${GREEN}Claude CLI is already installed: $(claude --version)${RC}"
        printf "%b" "${YELLOW}Do you want to update Claude CLI? [y/N] ${RC}"
        read -r update_choice
        case "$update_choice" in
            y | Y)
                printf "%b\n" "${CYAN}Updating Claude CLI...${RC}"
                curl -fsSL https://claude.ai/install.sh | bash
                printf "%b\n" "${GREEN}Claude CLI updated successfully.${RC}"
                ;;
            *)
                printf "%b\n" "${CYAN}Skipping update.${RC}"
                ;;
        esac
    else
        printf "%b\n" "${CYAN}Installing Claude CLI...${RC}"
        curl -fsSL https://claude.ai/install.sh | bash
        printf "%b\n" "${GREEN}Claude CLI installed successfully.${RC}"
        printf "%b\n" "${YELLOW}Run 'claude' to get started. You will be prompted to log in on first launch.${RC}"
    fi
}

checkEnv
checkRoot
installClaude
