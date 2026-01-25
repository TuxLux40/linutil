#!/bin/sh -e

. ../../common-script.sh

install_socktop() {
    printf "%b\n" "${YELLOW}Installing socktop...${RC}"
    
    # Check and install Rust
    checkRust
    
    # Install binaries via cargo
    printf "%b\n" "${CYAN}Installing socktop TUI client...${RC}"
    if cargo install socktop --locked; then
        printf "%b\n" "${GREEN}socktop TUI installed successfully!${RC}"
    else
        printf "%b\n" "${RED}Failed to install socktop TUI.${RC}"
        return 1
    fi
    
    printf "%b\n" "${CYAN}Installing socktop_agent (server)...${RC}"
    if cargo install socktop_agent --locked; then
        printf "%b\n" "${GREEN}socktop_agent installed successfully!${RC}"
    else
        printf "%b\n" "${RED}Failed to install socktop_agent.${RC}"
        return 1
    fi
    
    # Verify installation
    if command_exists socktop && command_exists socktop_agent; then
        printf "%b\n" "${GREEN}✓ socktop installation completed!${RC}"
        printf "%b\n" "${CYAN}Usage:${RC}"
        printf "%b\n" "${CYAN}  Server (on target machine):${RC}"
        printf "%b\n" "${CYAN}    socktop_agent --port 3000${RC}"
        printf "%b\n" "${CYAN}  Client (on local machine):${RC}"
        printf "%b\n" "${CYAN}    socktop ws://REMOTE_HOST:3000/ws${RC}"
        printf "%b\n" "${CYAN}  Demo (local):${RC}"
        printf "%b\n" "${CYAN}    socktop --demo${RC}"
    else
        printf "%b\n" "${RED}Installation verification failed.${RC}"
        return 1
    fi
}

checkEnv
checkEscalationTool
install_socktop