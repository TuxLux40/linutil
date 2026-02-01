#!/bin/sh -e

. ../../common-script.sh

install_kyanos() {
    printf "%b\n" "${YELLOW}Installing Kyanos...${RC}"
    
    # Kyanos requires Linux kernel 3.10+ 
    KERNEL_VERSION=$(uname -r | cut -d. -f1-2)
    printf "%b\n" "${CYAN}Kernel version: $(uname -r)${RC}"
    
    # Download latest release
    printf "%b\n" "${CYAN}Downloading Kyanos from GitHub releases...${RC}"
    
    # Get architecture
    checkArch
    
    # Determine download URL based on architecture
    DOWNLOAD_URL="https://github.com/hengyoush/kyanos/releases/download/v1.5.0/kyanos_v1.5.0_linux_${ARCH}.tar.gz"
    TEMP_DIR="/tmp/kyanos_install"
    
    mkdir -p "$TEMP_DIR"
    cd "$TEMP_DIR"
    
    if curl -L "$DOWNLOAD_URL" -o kyanos.tar.gz; then
        printf "%b\n" "${GREEN}Downloaded successfully.${RC}"
    else
        printf "%b\n" "${RED}Failed to download Kyanos.${RC}"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Extract archive
    printf "%b\n" "${CYAN}Extracting Kyanos...${RC}"
    tar xzf kyanos.tar.gz
    
    # Install binary
    printf "%b\n" "${CYAN}Installing Kyanos binary...${RC}"
    if [ -f "kyanos" ]; then
        "$ESCALATION_TOOL" install -o root -g root -m 0755 kyanos /usr/local/bin/kyanos
        printf "%b\n" "${GREEN}Kyanos installed successfully!${RC}"
    else
        printf "%b\n" "${RED}kyanos binary not found in archive.${RC}"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Cleanup
    cd /
    rm -rf "$TEMP_DIR"
    
    # Verify installation
    if command_exists kyanos; then
        printf "%b\n" "${GREEN}✓ Kyanos installation completed!${RC}"
        printf "%b\n" "${CYAN}Usage:${RC}"
        printf "%b\n" "${CYAN}  sudo kyanos watch (capture all traffic)${RC}"
        printf "%b\n" "${CYAN}  sudo kyanos watch http (capture HTTP traffic)${RC}"
        printf "%b\n" "${CYAN}  sudo kyanos watch redis (capture Redis traffic)${RC}"
        printf "%b\n" "${CYAN}  sudo kyanos stat --slow --time 5 (show slowest requests)${RC}"
        printf "%b\n" "${YELLOW}Note: Kyanos requires root privileges.${RC}"
    else
        printf "%b\n" "${RED}Installation verification failed.${RC}"
        return 1
    fi
}

checkEnv
checkEscalationTool
install_kyanos