#!/bin/sh -e

. ../../common-script.sh

install_lazynginx() {
    printf "%b\n" "${YELLOW}Installing LazyNginx...${RC}"

    # Check if Go is installed
    if ! command_exists go; then
        printf "%b\n" "${RED}Go is not installed!${RC}"
        printf "%b\n" "${YELLOW}Please install Go 1.21+ first using 'System Setup' -> 'Build Setup'${RC}"
        return 1
    fi

    # Check if Nginx is installed
    if ! command_exists nginx; then
        printf "%b\n" "${YELLOW}Nginx is not installed on this system.${RC}"
        printf "%b\n" "${YELLOW}LazyNginx requires Nginx to be installed. Installing now...${RC}"
        
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm nginx
                ;;
            apt-get|nala)
                "$ESCALATION_TOOL" "$PACKAGER" update
                "$ESCALATION_TOOL" "$PACKAGER" install -y nginx
                ;;
            dnf)
                "$ESCALATION_TOOL" "$PACKAGER" install -y nginx
                ;;
            zypper)
                "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install nginx
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add nginx
                ;;
            *)
                printf "%b\n" "${RED}Nginx installation not supported for this package manager.${RC}"
                printf "%b\n" "${YELLOW}Please install Nginx manually and try again.${RC}"
                return 1
                ;;
        esac
    else
        printf "%b\n" "${GREEN}✓ Nginx is installed${RC}"
    fi

    # Create temporary directory for the build
    TEMP_DIR="/tmp/lazynginx_build"
    printf "%b\n" "${CYAN}Cloning LazyNginx from GitHub...${RC}"

    if [ -d "$TEMP_DIR" ]; then
        rm -rf "$TEMP_DIR"
    fi

    if ! git clone https://github.com/giacomomasseron/lazynginx.git "$TEMP_DIR"; then
        printf "%b\n" "${RED}Failed to clone LazyNginx repository.${RC}"
        return 1
    fi

    cd "$TEMP_DIR"

    # Download dependencies
    printf "%b\n" "${CYAN}Downloading Go dependencies...${RC}"
    if ! go mod download; then
        printf "%b\n" "${RED}Failed to download dependencies.${RC}"
        return 1
    fi

    # Build the application
    printf "%b\n" "${CYAN}Building LazyNginx...${RC}"
    if ! go build -o lazynginx; then
        printf "%b\n" "${RED}Failed to build LazyNginx.${RC}"
        return 1
    fi

    # Install the binary
    printf "%b\n" "${CYAN}Installing LazyNginx binary to /usr/local/bin...${RC}"
    "$ESCALATION_TOOL" mkdir -p /usr/local/bin
    "$ESCALATION_TOOL" cp lazynginx /usr/local/bin/
    "$ESCALATION_TOOL" chmod +x /usr/local/bin/lazynginx

    # Clean up
    cd /
    rm -rf "$TEMP_DIR"

    if command_exists lazynginx; then
        printf "%b\n" "${GREEN}✓ LazyNginx installed successfully!${RC}"
        printf "%b\n" "${CYAN}Usage:${RC}"
        printf "%b\n" "${CYAN}  sudo lazynginx${RC}"
        printf "%b\n" "${YELLOW}Note: Some operations require sudo/administrator privileges.${RC}"
        printf "%b\n" "${CYAN}Navigation Controls:${RC}"
        printf "%b\n" "${CYAN}  ↑/↓ or k/j: Navigate menu${RC}"
        printf "%b\n" "${CYAN}  Enter: Select option${RC}"
        printf "%b\n" "${CYAN}  q or Ctrl+C: Quit application${RC}"
    else
        printf "%b\n" "${RED}Installation verification failed.${RC}"
        return 1
    fi
}

checkEnv
checkEscalationTool
install_lazynginx
