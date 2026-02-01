#!/bin/sh -e

. ../../common-script.sh

setup_go_path() {
    if ! command_exists go; then
        printf "%b\n" "${RED}Go is not installed. Please install Go first using the Build Setup option.${RC}"
        return 1
    fi

    GOPATH=$(go env GOPATH)
    GOBIN="$GOPATH/bin"
    
    printf "%b\n" "${YELLOW}Setting up Go PATH configuration...${RC}"
    printf "%b\n" "${CYAN}GOPATH: $GOPATH${RC}"
    printf "%b\n" "${CYAN}GOBIN: $GOBIN${RC}"

    # Setup for bash
    if [ -f "$HOME/.bashrc" ]; then
        if ! grep -q "GOPATH/bin" "$HOME/.bashrc" 2>/dev/null; then
            printf "\n# Add Go bin to PATH\n" >> "$HOME/.bashrc"
            printf 'export PATH="$PATH:$(go env GOPATH)/bin"\n' >> "$HOME/.bashrc"
            printf "%b\n" "${GREEN}Added GOPATH/bin to ~/.bashrc${RC}"
        else
            printf "%b\n" "${GREEN}GOPATH/bin already in ~/.bashrc${RC}"
        fi
    fi

    # Setup for zsh
    if [ -f "$HOME/.zshrc" ]; then
        if ! grep -q "GOPATH/bin" "$HOME/.zshrc" 2>/dev/null; then
            printf "\n# Add Go bin to PATH\n" >> "$HOME/.zshrc"
            printf 'export PATH="$PATH:$(go env GOPATH)/bin"\n' >> "$HOME/.zshrc"
            printf "%b\n" "${GREEN}Added GOPATH/bin to ~/.zshrc${RC}"
        else
            printf "%b\n" "${GREEN}GOPATH/bin already in ~/.zshrc${RC}"
        fi
    fi

    # Setup for fish
    FISH_CONFIG="$HOME/.config/fish/config.fish"
    if [ -f "$FISH_CONFIG" ]; then
        if ! grep -q "GOPATH.*bin" "$FISH_CONFIG" 2>/dev/null; then
            mkdir -p "$HOME/.config/fish"
            printf "\n# Add Go bin to PATH\n" >> "$FISH_CONFIG"
            printf 'if test -d (go env GOPATH)/bin\n' >> "$FISH_CONFIG"
            printf '    fish_add_path (go env GOPATH)/bin\n' >> "$FISH_CONFIG"
            printf 'end\n' >> "$FISH_CONFIG"
            printf "%b\n" "${GREEN}Added GOPATH/bin to fish config${RC}"
        else
            printf "%b\n" "${GREEN}GOPATH/bin already in fish config${RC}"
        fi
    fi

    printf "%b\n" "${GREEN}Go PATH setup completed!${RC}"
    printf "%b\n" "${YELLOW}Please restart your shell or run:${RC}"
    printf "%b\n" "${CYAN}  - For bash/zsh: source ~/.bashrc or source ~/.zshrc${RC}"
    printf "%b\n" "${CYAN}  - For fish: source ~/.config/fish/config.fish${RC}"
    printf "%b\n" "${CYAN}  - Or simply open a new terminal${RC}"
}

checkEnv
setup_go_path
