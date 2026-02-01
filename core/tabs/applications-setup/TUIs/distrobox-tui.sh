#!/bin/sh -e

. ../../common-script.sh

install_distrobox_tui() {
    printf "%b\n" "${YELLOW}Installing distrobox-tui...${RC}"
    
    # Check if Go is installed
    if ! command_exists go; then
        printf "%b\n" "${RED}Go is not installed!${RC}"
        printf "%b\n" "${YELLOW}Please install Go first using 'System Setup' -> 'Build Setup'${RC}"
        return 1
    fi
    
    # Check Go version
    GO_VERSION=$(go version | awk '{print $3}' | sed 's/go//')
    printf "%b\n" "${CYAN}Found Go version: $GO_VERSION${RC}"
    
    # Check if distrobox is installed
    if ! command_exists distrobox; then
        printf "%b\n" "${YELLOW}Distrobox is not installed. Installing distrobox...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm distrobox
                ;;
            apt-get|nala)
                "$ESCALATION_TOOL" "$PACKAGER" update
                "$ESCALATION_TOOL" "$PACKAGER" install -y distrobox
                ;;
            dnf)
                "$ESCALATION_TOOL" "$PACKAGER" install -y distrobox
                ;;
            zypper)
                "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install distrobox
                ;;
            *)
                printf "%b\n" "${RED}Distrobox installation not supported for this package manager.${RC}"
                printf "%b\n" "${YELLOW}Please install distrobox manually from: https://github.com/89luca89/distrobox${RC}"
                return 1
                ;;
        esac
    else
        printf "%b\n" "${GREEN}Distrobox is already installed.${RC}"
    fi
    
    # Check if podman or docker is available
    if ! command_exists podman && ! command_exists docker; then
        printf "%b\n" "${YELLOW}Neither podman nor docker is installed.${RC}"
        printf "%b\n" "${YELLOW}Distrobox requires a container engine. Would you like to install podman? (recommended)${RC}"
        printf "%b" "${GREEN}Install podman? [Y/n]: ${RC}"
        read -r response
        case "$response" in
            [nN]|[nN][oO])
                printf "%b\n" "${YELLOW}Skipping container engine installation. Please install podman or docker manually.${RC}"
                ;;
            *)
                case "$PACKAGER" in
                    pacman)
                        "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm podman
                        ;;
                    apt-get|nala)
                        "$ESCALATION_TOOL" "$PACKAGER" update
                        "$ESCALATION_TOOL" "$PACKAGER" install -y podman
                        ;;
                    dnf)
                        "$ESCALATION_TOOL" "$PACKAGER" install -y podman
                        ;;
                    zypper)
                        "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install podman
                        ;;
                    *)
                        printf "%b\n" "${RED}Podman installation not supported for this package manager.${RC}"
                        return 1
                        ;;
                esac
                printf "%b\n" "${GREEN}Podman installed successfully.${RC}"
                ;;
        esac
    fi
    
    # Check if GOPATH/bin is in PATH
    GOPATH=$(go env GOPATH)
    GOBIN="$GOPATH/bin"
    
    if ! echo "$PATH" | grep -q "$GOBIN"; then
        printf "%b\n" "${YELLOW}Warning: $GOBIN is not in your PATH!${RC}"
        printf "%b\n" "${CYAN}After installation, you should run 'Developer Tools' -> 'Go Setup' to configure your PATH${RC}"
    fi
    
    # Install distrobox-tui using go install
    printf "%b\n" "${CYAN}Installing distrobox-tui from source...${RC}"
    if go install github.com/phanirithvij/distrobox-tui@main; then
        printf "%b\n" "${GREEN}distrobox-tui installed successfully!${RC}"
        printf "%b\n" "${CYAN}Installation location: $GOBIN/distrobox-tui${RC}"
        
        if echo "$PATH" | grep -q "$GOBIN"; then
            printf "%b\n" "${GREEN}You can now run: distrobox-tui${RC}"
        else
            printf "%b\n" "${YELLOW}To use distrobox-tui, either:${RC}"
            printf "%b\n" "${CYAN}  1. Run: $GOBIN/distrobox-tui${RC}"
            printf "%b\n" "${CYAN}  2. Or configure Go PATH by running 'Developer Tools' -> 'Go Setup'${RC}"
        fi
        
        printf "%b\n" "${CYAN}Usage:${RC}"
        printf "%b\n" "${CYAN}  - distrobox-tui (auto-detects podman/docker/lilipod)${RC}"
        printf "%b\n" "${CYAN}  - DBX_CONTAINER_MANAGER=podman distrobox-tui${RC}"
        printf "%b\n" "${CYAN}  - DBX_CONTAINER_MANAGER=docker distrobox-tui${RC}"
    else
        printf "%b\n" "${RED}Failed to install distrobox-tui${RC}"
        return 1
    fi
}

checkEnv
checkEscalationTool
install_distrobox_tui
