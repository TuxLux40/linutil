#!/bin/sh -e

. ../common-script.sh

# Snowflake Proxy - Install from Source
# Based on: https://community.torproject.org/relay/setup/snowflake/standalone/source/

installSnowflake() {
    clear
    printf "%b\n" "${YELLOW}Installing Snowflake Proxy from source...${RC}"
    
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm go git
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y golang git
            ;;
        dnf|yum)
            "$ESCALATION_TOOL" "$PACKAGER" install -y golang git
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y go git
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: ${PACKAGER}${RC}"
            exit 1
            ;;
    esac
    
    # Check Go version
    printf "%b\n" "${YELLOW}Checking Go version...${RC}"
    go_version=$(go version | awk '{print $3}' | sed 's/go//')
    required_version="1.21"
    
    if [ "$(printf '%s\n' "$required_version" "$go_version" | sort -V | head -n1)" != "$required_version" ]; then
        printf "%b\n" "${RED}Go version $go_version is too old. Required: $required_version or newer${RC}"
        printf "%b\n" "${YELLOW}Please install a newer version from https://golang.org/dl/${RC}"
        exit 1
    fi
    
    printf "%b\n" "${GREEN}Go version $go_version is sufficient${RC}"
    
    # Clone repository
    printf "%b\n" "${YELLOW}Cloning Snowflake repository...${RC}"
    cd "$HOME" || exit 1
    
    if [ -d "$HOME/snowflake" ]; then
        printf "%b\n" "${YELLOW}Snowflake directory already exists. Updating...${RC}"
        cd "$HOME/snowflake" || exit 1
        git pull
    else
        git clone https://gitlab.torproject.org/tpo/anti-censorship/pluggable-transports/snowflake.git
        cd "$HOME/snowflake" || exit 1
    fi
    
    # Build proxy
    printf "%b\n" "${YELLOW}Building Snowflake proxy...${RC}"
    cd "$HOME/snowflake/proxy" || exit 1
    go build
    
    if [ ! -f "$HOME/snowflake/proxy/proxy" ]; then
        printf "%b\n" "${RED}Build failed. Proxy binary not found.${RC}"
        exit 1
    fi
    
    printf "%b\n" "${GREEN}Snowflake proxy built successfully!${RC}"
    
    # Setup systemd service
    printf "%b\n" "${YELLOW}Setting up systemd service...${RC}"
    
    cat << EOF | "$ESCALATION_TOOL" tee /etc/systemd/system/snowflake-proxy.service > /dev/null
[Unit]
Description=Snowflake Proxy
After=network.target

[Service]
Type=simple
User=$USER
WorkingDirectory=$HOME/snowflake/proxy
ExecStart=$HOME/snowflake/proxy/proxy
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF
    
    "$ESCALATION_TOOL" systemctl daemon-reload
    "$ESCALATION_TOOL" systemctl enable snowflake-proxy.service
    "$ESCALATION_TOOL" systemctl start snowflake-proxy.service
    
    printf "%b\n" "${GREEN}Snowflake proxy installed and started!${RC}"
    printf "%b\n" "${YELLOW}Check status with: systemctl status snowflake-proxy${RC}"
    printf "%b\n" "${YELLOW}View logs with: journalctl -u snowflake-proxy -f${RC}"
    printf "%b\n" "${YELLOW}To update later, run this script again or manually:${RC}"
    printf "%b\n" "  cd $HOME/snowflake && git pull && cd proxy && go build"
    printf "%b\n" "  sudo systemctl restart snowflake-proxy"
}

checkEnv
checkEscalationTool
installSnowflake
