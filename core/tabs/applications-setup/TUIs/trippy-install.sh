#!/bin/sh -e

. ../../common-script.sh

install_trippy() {
    printf "%b\n" "${YELLOW}Installing Trippy...${RC}"
    
    # Check and install Rust
    checkRust
    
    # Install trippy via cargo
    printf "%b\n" "${CYAN}Installing trippy (network diagnostic tool)...${RC}"
    if cargo install trippy --locked; then
        printf "%b\n" "${GREEN}Trippy installed successfully!${RC}"
    else
        printf "%b\n" "${RED}Failed to install Trippy.${RC}"
        return 1
    fi
    
    # Verify installation
    if command_exists trip; then
        printf "%b\n" "${GREEN}✓ Trippy installation completed!${RC}"
        printf "%b\n" "${CYAN}Usage:${RC}"
        printf "%b\n" "${CYAN}  sudo trip example.com${RC}"
        printf "%b\n" "${CYAN}  trip -h (for help)${RC}"
        printf "%b\n" "${YELLOW}Note: Trippy requires elevated privileges to run.${RC}"
    else
        printf "%b\n" "${RED}Installation verification failed.${RC}"
        return 1
    fi
}

checkEnv
checkEscalationTool
install_trippy