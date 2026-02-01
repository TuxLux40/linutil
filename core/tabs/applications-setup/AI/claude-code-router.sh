#!/bin/sh -e

# Claude Code Router Installation Script with Ollama Integration
# Installs and configures Claude Code Router for use with Ollama

. ../common-script.sh

checkEnv

# Check root privileges
checkRoot() {
    if [ "$(id -u)" -eq 0 ]; then
        printf "%b\n" "${RED}This script should not be run as root!${RC}"
        exit 1
    fi
}

# Check dependencies
checkDependencies() {
    printf "%b\n" "${CYAN}Checking system dependencies...${RC}"

    # Check Node.js
    if ! command_exists node; then
        printf "%b\n" "${RED}Node.js is not installed!${RC}"
        printf "%b\n" "${CYAN}Install Node.js (minimum version 18.0.0)...${RC}"
        printf "%b\n" "${CYAN}Arch Linux: sudo pacman -S nodejs npm${RC}"
        exit 1
    fi

    NODE_VERSION=$(node -v | cut -d'v' -f2 | cut -d'.' -f1)
    if [ "$NODE_VERSION" -lt 18 ]; then
        printf "%b\n" "${RED}Node.js version 18.0.0 or higher is required. Current version: $(node -v)${RC}"
        exit 1
    fi

    printf "%b\n" "${GREEN}Node.js version: $(node -v)${RC}"

    # Check npm
    if ! command_exists npm; then
        printf "%b\n" "${RED}npm is not installed!${RC}"
        exit 1
    fi
    printf "%b\n" "${GREEN}npm version: $(npm -v)${RC}"

    # Check Ollama
    if ! command_exists ollama; then
        printf "%b\n" "${YELLOW}Ollama is not installed!${RC}"
        printf "%b\n" "${CYAN}Install Ollama: curl -fsSL https://ollama.com/install.sh | sh${RC}"
        printf "%b" "${GREEN}Do you want to install Ollama now? [y/N] ${RC}"
        read -r install_ollama
        if [ "$install_ollama" = "y" ] || [ "$install_ollama" = "Y" ]; then
            curl -fsSL https://ollama.com/install.sh | sh
            printf "%b\n" "${GREEN}Ollama has been installed${RC}"
        else
            printf "%b\n" "${YELLOW}Claude Code Router cannot be fully configured without Ollama${RC}"
        fi
    else
        printf "%b\n" "${GREEN}Ollama is already installed: $(ollama --version)${RC}"
    fi
}

# Install Claude Code Router
installClaudeCodeRouter() {
    printf "%b\n" "${CYAN}Installing Claude Code Router globally...${RC}"

    # Check if using npm prefix that requires sudo
    NPM_PREFIX=$(npm config get prefix)
    NEED_SUDO="false"

    if [ "$NPM_PREFIX" = "/usr" ] || [ "$NPM_PREFIX" = "/usr/local" ]; then
        NEED_SUDO="true"
    fi

    # Use npm for global installation
    if npm list -g @musistudio/claude-code-router >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Claude Code Router is already installed${RC}"
        printf "%b" "${GREEN}Do you want to update the installation? [y/N] ${RC}"
        read -r update_ccr
        if [ "$update_ccr" = "y" ] || [ "$update_ccr" = "Y" ]; then
            if [ "$NEED_SUDO" = "true" ]; then
                printf "%b\n" "${CYAN}Requires sudo for global npm packages...${RC}"
                sudo npm update -g @musistudio/claude-code-router
            else
                npm update -g @musistudio/claude-code-router
            fi
            printf "%b\n" "${GREEN}Claude Code Router has been updated${RC}"
        fi
    else
        if [ "$NEED_SUDO" = "true" ]; then
            printf "%b\n" "${CYAN}Requires sudo for global npm packages...${RC}"
            sudo npm install -g @musistudio/claude-code-router
        else
            npm install -g @musistudio/claude-code-router
        fi
        printf "%b\n" "${GREEN}Claude Code Router has been installed${RC}"
    fi

    # Verify installation
    if command_exists ccr; then
        printf "%b\n" "${GREEN}Claude Code Router version: $(ccr --version)${RC}"
    else
        printf "%b\n" "${RED}Installation failed! ccr command not available${RC}"
        printf "%b\n" "${CYAN}Tip: Consider using nvm (Node Version Manager) to avoid permission issues${RC}"
        exit 1
    fi
}

# Install Ollama models
setupOllamaModels() {
    printf "%b\n" "${CYAN}Setting up Ollama models...${RC}"

    if ! command_exists ollama; then
        printf "%b\n" "${YELLOW}Ollama is not available. Skipping model installation${RC}"
        return
    fi

    # Check if Ollama service is running
    if ! systemctl --user is-active --quiet ollama 2>/dev/null && ! pgrep -x ollama >/dev/null 2>&1; then
        printf "%b\n" "${CYAN}Starting Ollama service...${RC}"
        if systemctl --user start ollama 2>/dev/null; then
            printf "%b\n" "${GREEN}Ollama service has been started${RC}"
        else
            printf "%b\n" "${YELLOW}Could not start Ollama service. Trying manual start...${RC}"
            ollama serve >/dev/null 2>&1 &
            sleep 3
        fi
    fi

    # Recommended models
    printf "%b\n" "${CYAN}Available recommended models:${RC}"
    printf "%b\n" "${CYAN}  1. qwen2.5-coder:latest${RC}"
    printf "%b\n" "${CYAN}  2. deepseek-r1:8b${RC}"
    printf "%b\n" "${CYAN}  3. llama3.2:latest${RC}"

    printf "%b" "${GREEN}Which models do you want to install? (space-separated numbers, Enter for qwen2.5-coder): ${RC}"
    read -r model_choice

    if [ -z "$model_choice" ]; then
        model_choice="1"
    fi

    MODELS="qwen2.5-coder:latest deepseek-r1:8b llama3.2:latest"
    MODEL_ARRAY="$MODELS"

    COUNT=1
    for model in $MODEL_ARRAY; do
        if echo "$model_choice" | grep -q "$COUNT"; then
            printf "%b\n" "${CYAN}Installing model: $model (This may take some time)...${RC}"
            if ollama pull "$model"; then
                printf "%b\n" "${GREEN}Model $model has been installed${RC}"
            else
                printf "%b\n" "${RED}Error installing $model${RC}"
            fi
        fi
        COUNT=$((COUNT + 1))
    done
}

# Configure Claude Code Router
configureClaudeCodeRouter() {
    printf "%b\n" "${CYAN}Configuring Claude Code Router...${RC}"

    CONFIG_DIR="$HOME/.claude-code-router"
    CONFIG_FILE="$CONFIG_DIR/config.json"

    # Create configuration directory
    mkdir -p "$CONFIG_DIR"

    # Ask for Ollama URL
    OLLAMA_URL="http://localhost:11434"
    printf "%b" "${GREEN}Ollama API URL (default: $OLLAMA_URL): ${RC}"
    read -r custom_ollama_url
    if [ -n "$custom_ollama_url" ]; then
        OLLAMA_URL="$custom_ollama_url"
    fi

    # Detect installed models
    printf "%b\n" "${CYAN}Detecting installed Ollama models...${RC}"
    AVAILABLE_MODELS=""
    if command_exists ollama; then
        AVAILABLE_MODELS=$(ollama list 2>/dev/null | tail -n +2 | awk '{print $1}' | tr '\n' ',' | sed 's/,$//')
    fi

    if [ -z "$AVAILABLE_MODELS" ]; then
        AVAILABLE_MODELS="qwen2.5-coder:latest"
        printf "%b\n" "${YELLOW}No Ollama models found. Using default: $AVAILABLE_MODELS${RC}"
    else
        printf "%b\n" "${GREEN}Found models: $AVAILABLE_MODELS${RC}"
    fi

    # Ask for default models
    printf "%b\n" "${CYAN}Choose default models for different tasks:${RC}"
    printf "%b\n" "${CYAN}  1. default   - Main model for normal requests${RC}"
    printf "%b\n" "${CYAN}  2. background - Fast model for background tasks${RC}"
    printf "%b\n" "${CYAN}  3. think     - Model for complex reasoning${RC}"

    printf "%b" "${GREEN}Default model for 'default' (Enter for qwen2.5-coder:latest): ${RC}"
    read -r default_model
    default_model=${default_model:-qwen2.5-coder:latest}

    printf "%b" "${GREEN}Default model for 'background' (Enter for $default_model): ${RC}"
    read -r background_model
    background_model=${background_model:-$default_model}

    printf "%b" "${GREEN}Default model for 'think' (Enter for deepseek-r1:8b): ${RC}"
    read -r think_model
    think_model=${think_model:-deepseek-r1:8b}

    # Create configuration file
    printf "%b\n" "${CYAN}Creating configuration file: $CONFIG_FILE${RC}"

    cat > "$CONFIG_FILE" <<EOF
{
  "PORT": 3456,
  "HOST": "127.0.0.1",
  "LOG": true,
  "LOG_LEVEL": "info",
  "API_TIMEOUT_MS": 600000,

  "Providers": [
    {
      "name": "ollama",
      "api_base_url": "${OLLAMA_URL}/v1/chat/completions",
      "api_key": "ollama",
      "models": [$(echo "$AVAILABLE_MODELS" | sed 's/,/", "/g' | sed 's/^/"/' | sed 's/$/"/')]
    }
  ],

  "Router": {
    "default": "ollama,${default_model}",
    "background": "ollama,${background_model}",
    "think": "ollama,${think_model}",
    "longContextThreshold": 60000
  },

  "transformers": []
}
EOF

    printf "%b\n" "${GREEN}Configuration file has been created${RC}"
    printf "%b\n" "${CYAN}Configuration saved to: $CONFIG_FILE${RC}"
}

# Create systemd service (optional)
createSystemdService() {
    printf "%b\n" "${CYAN}Do you want to create a systemd service for Claude Code Router?${RC}"
    printf "%b" "${GREEN}This will start the server automatically on system boot [y/N] ${RC}"
    read -r create_service

    if [ "$create_service" != "y" ] && [ "$create_service" != "Y" ]; then
        return
    fi

    SERVICE_DIR="$HOME/.config/systemd/user"
    SERVICE_FILE="$SERVICE_DIR/claude-code-router.service"

    mkdir -p "$SERVICE_DIR"

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Claude Code Router Service
After=network.target

[Service]
Type=simple
ExecStart=$(command -v ccr) server
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=default.target
EOF

    printf "%b\n" "${GREEN}Systemd service has been created: $SERVICE_FILE${RC}"

    # Enable and start service
    systemctl --user daemon-reload
    systemctl --user enable claude-code-router.service
    systemctl --user start claude-code-router.service

    printf "%b\n" "${GREEN}Service has been enabled and started${RC}"
    printf "%b\n" "${CYAN}Service status: systemctl --user status claude-code-router${RC}"
    printf "%b\n" "${CYAN}Service logs: journalctl --user -u claude-code-router -f${RC}"
}

# Claude Code Extension Setup
setupClaudeCodeExtension() {
    printf "%b\n" "${CYAN}Claude Code VSCode Extension Setup...${RC}"
    printf "%b\n" ""
    printf "%b\n" "${CYAN}To use Claude Code Router with the Claude Code Extension:${RC}"
    printf "%b\n" "${CYAN}1. Install the Claude Code Extension in VSCode${RC}"
    printf "%b\n" "${CYAN}2. Set the environment variables:${RC}"
    printf "\n"
    printf "%b\n" "${GREEN}export ANTHROPIC_BASE_URL=\"http://127.0.0.1:3456\"${RC}"
    printf "%b\n" "${GREEN}export ANTHROPIC_API_KEY=\"dummy-key\"${RC}"
    printf "\n"
    printf "%b\n" "${CYAN}3. Add these lines to your ~/.bashrc or ~/.zshrc${RC}"
    printf "%b\n" "${CYAN}4. Restart VSCode${RC}"
    printf "\n"

    printf "%b" "${GREEN}Do you want to add the environment variables to ~/.bashrc now? [y/N] ${RC}"
    read -r add_env

    if [ "$add_env" = "y" ] || [ "$add_env" = "Y" ]; then
        {
            echo ""
            echo "# Claude Code Router Configuration"
            echo "export ANTHROPIC_BASE_URL=\"http://127.0.0.1:3456\""
            echo "export ANTHROPIC_API_KEY=\"dummy-key\""
        } >> "$HOME/.bashrc"
        printf "%b\n" "${GREEN}Environment variables have been added to ~/.bashrc${RC}"
        printf "%b\n" "${YELLOW}Run 'source ~/.bashrc' or open a new terminal${RC}"
    fi
}

# Test installation
testInstallation() {
    printf "%b\n" "${CYAN}Testing Claude Code Router installation...${RC}"

    # Test ccr command
    if ! command_exists ccr; then
        printf "%b\n" "${RED}ccr command not found!${RC}"
        return 1
    fi

    # Test configuration
    if [ -f "$HOME/.claude-code-router/config.json" ]; then
        printf "%b\n" "${GREEN}Configuration file found${RC}"
    else
        printf "%b\n" "${YELLOW}Configuration file not found${RC}"
    fi

    # Test Ollama connection
    if command_exists ollama; then
        if ollama list >/dev/null 2>&1; then
            printf "%b\n" "${GREEN}Ollama is reachable${RC}"
        else
            printf "%b\n" "${YELLOW}Ollama is not reachable${RC}"
        fi
    fi

    printf "\n"
    printf "%b\n" "${CYAN}Installation completed!${RC}"
    printf "\n"
    printf "%b\n" "${CYAN}Next steps:${RC}"
    printf "%b\n" "${CYAN}1. Start the server: ccr server${RC}"
    printf "%b\n" "${CYAN}2. Or use CLI mode: ccr \"your query\"${RC}"
    printf "%b\n" "${CYAN}3. Or open the Web UI: ccr ui${RC}"
    printf "%b\n" "${CYAN}4. Edit configuration: nano ~/.claude-code-router/config.json${RC}"
    printf "\n"
    printf "%b\n" "${CYAN}Documentation: https://github.com/musistudio/claude-code-router${RC}"
}

# Main function
main() {
    printf "\n"
    printf "%b\n" "${CYAN}================================================${RC}"
    printf "%b\n" "${CYAN}  Claude Code Router Installation with Ollama${RC}"
    printf "%b\n" "${CYAN}================================================${RC}"
    printf "\n"

    checkRoot
    checkDependencies
    installClaudeCodeRouter
    setupOllamaModels
    configureClaudeCodeRouter
    createSystemdService
    setupClaudeCodeExtension
    testInstallation

    printf "\n"
    printf "%b\n" "${GREEN}✓ Installation completed successfully!${RC}"
    printf "\n"
}

# Start script
main "$@"
