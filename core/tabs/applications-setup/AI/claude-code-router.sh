#!/bin/sh -e

# Claude Code Router Installation Script with Ollama Integration
# Installs and configures Claude Code Router for use with Ollama

. ../../common-script.sh

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

    # Make sure npm global bin is on PATH for current script session
    NPM_BIN="$(npm config get prefix 2>/dev/null)/bin"
    case ":$PATH:" in
        *":$NPM_BIN:"*) ;;
        *) PATH="$NPM_BIN:$PATH"; export PATH ;;
    esac

    # Verify installation
    if command_exists ccr; then
        printf "%b\n" "${GREEN}Claude Code Router version: $(ccr --version)${RC}"
    else
        printf "%b\n" "${RED}ccr command not on PATH${RC}"
        printf "%b\n" "${CYAN}npm global bin: ${NPM_BIN}${RC}"
        printf "%b\n" "${CYAN}Add this to your shell rc: export PATH=\"${NPM_BIN}:\$PATH\"${RC}"
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

    # Ollama installer creates a system service, not a user service
    if ! pgrep -x ollama >/dev/null 2>&1 && ! systemctl is-active --quiet ollama 2>/dev/null; then
        printf "%b\n" "${CYAN}Starting Ollama service...${RC}"
        if systemctl list-unit-files ollama.service >/dev/null 2>&1; then
            if "$ESCALATION_TOOL" systemctl start ollama; then
                printf "%b\n" "${GREEN}Ollama service has been started${RC}"
            else
                printf "%b\n" "${YELLOW}systemctl start failed. Trying manual start...${RC}"
                ollama serve >/dev/null 2>&1 &
                sleep 3
            fi
        else
            printf "%b\n" "${YELLOW}No ollama.service found. Starting manually...${RC}"
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

    # Tokenize user input so "12" does not accidentally match model index 12
    for token in $model_choice; do
        COUNT=1
        for model in $MODELS; do
            if [ "$token" = "$COUNT" ]; then
                printf "%b\n" "${CYAN}Installing model: $model (This may take some time)...${RC}"
                if ollama pull "$model"; then
                    printf "%b\n" "${GREEN}Model $model has been installed${RC}"
                else
                    printf "%b\n" "${RED}Error installing $model${RC}"
                fi
                break
            fi
            COUNT=$((COUNT + 1))
        done
    done
}

models_to_json_array() {
    # Convert a comma-separated list into a JSON string array
    echo "$1" | awk -F',' '{
        printf "["
        for (i = 1; i <= NF; i++) {
            gsub(/^ +| +$/, "", $i)
            if ($i == "") continue
            if (i > 1) printf ", "
            printf "\"%s\"", $i
        }
        printf "]"
    }'
}

# Configure Claude Code Router
configureClaudeCodeRouter() {
    printf "%b\n" "${CYAN}Configuring Claude Code Router...${RC}"

    CONFIG_DIR="$HOME/.claude-code-router"
    CONFIG_FILE="$CONFIG_DIR/config.json"

    mkdir -p "$CONFIG_DIR"

    # Pick providers
    USE_OLLAMA="true"
    USE_OPENROUTER="false"
    printf "%b" "${GREEN}Add OpenRouter provider as well? [y/N] ${RC}"
    read -r want_or
    if [ "$want_or" = "y" ] || [ "$want_or" = "Y" ]; then
        USE_OPENROUTER="true"
    fi

    printf "%b" "${GREEN}Include Ollama provider? [Y/n] ${RC}"
    read -r want_ol
    if [ "$want_ol" = "n" ] || [ "$want_ol" = "N" ]; then
        USE_OLLAMA="false"
    fi

    if [ "$USE_OLLAMA" = "false" ] && [ "$USE_OPENROUTER" = "false" ]; then
        printf "%b\n" "${RED}At least one provider must be selected${RC}"
        exit 1
    fi

    OLLAMA_MODELS_JSON=""
    default_model=""
    background_model=""
    think_model=""
    long_model=""
    DEFAULT_PROVIDER=""

    if [ "$USE_OLLAMA" = "true" ]; then
        OLLAMA_URL="http://localhost:11434"
        printf "%b" "${GREEN}Ollama API URL (default: $OLLAMA_URL): ${RC}"
        read -r custom_ollama_url
        if [ -n "$custom_ollama_url" ]; then
            OLLAMA_URL="$custom_ollama_url"
        fi

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
        OLLAMA_MODELS_JSON=$(models_to_json_array "$AVAILABLE_MODELS")

        printf "%b" "${GREEN}Ollama default model (Enter for qwen2.5-coder:latest): ${RC}"
        read -r default_model
        default_model=${default_model:-qwen2.5-coder:latest}

        printf "%b" "${GREEN}Ollama background model (Enter for $default_model): ${RC}"
        read -r background_model
        background_model=${background_model:-$default_model}

        printf "%b" "${GREEN}Ollama think model (Enter for deepseek-r1:8b): ${RC}"
        read -r think_model
        think_model=${think_model:-deepseek-r1:8b}

        DEFAULT_PROVIDER="ollama"
    fi

    OPENROUTER_KEY=""
    OR_MODELS_JSON=""
    or_default=""
    or_background=""
    or_think=""
    or_long=""

    if [ "$USE_OPENROUTER" = "true" ]; then
        printf "%b" "${GREEN}OpenRouter API key (leave empty to use \$OPENROUTER_API_KEY env): ${RC}"
        read -r OPENROUTER_KEY
        if [ -z "$OPENROUTER_KEY" ]; then
            # shellcheck disable=SC2016  # literal $VAR for ccr env interpolation
            OPENROUTER_KEY='$OPENROUTER_API_KEY'
        fi

        OR_DEFAULT_MODELS="anthropic/claude-sonnet-4,anthropic/claude-3.7-sonnet:thinking,google/gemini-2.5-pro-preview,deepseek/deepseek-chat"
        printf "%b" "${GREEN}OpenRouter models (comma-separated, Enter for defaults): ${RC}"
        read -r or_models
        or_models=${or_models:-$OR_DEFAULT_MODELS}
        OR_MODELS_JSON=$(models_to_json_array "$or_models")

        printf "%b" "${GREEN}OpenRouter default model (Enter for anthropic/claude-sonnet-4): ${RC}"
        read -r or_default
        or_default=${or_default:-anthropic/claude-sonnet-4}

        printf "%b" "${GREEN}OpenRouter background model (Enter for deepseek/deepseek-chat): ${RC}"
        read -r or_background
        or_background=${or_background:-deepseek/deepseek-chat}

        printf "%b" "${GREEN}OpenRouter think model (Enter for anthropic/claude-3.7-sonnet:thinking): ${RC}"
        read -r or_think
        or_think=${or_think:-anthropic/claude-3.7-sonnet:thinking}

        printf "%b" "${GREEN}OpenRouter longContext model (Enter for google/gemini-2.5-pro-preview): ${RC}"
        read -r or_long
        or_long=${or_long:-google/gemini-2.5-pro-preview}

        if [ -z "$DEFAULT_PROVIDER" ]; then
            DEFAULT_PROVIDER="openrouter"
            default_model="$or_default"
            background_model="$or_background"
            think_model="$or_think"
            long_model="$or_long"
        else
            long_model="$or_long"
        fi
    fi

    # Build Providers array
    PROVIDERS_JSON=""
    if [ "$USE_OLLAMA" = "true" ]; then
        PROVIDERS_JSON=$(cat <<EOF
    {
      "name": "ollama",
      "api_base_url": "${OLLAMA_URL}/v1/chat/completions",
      "api_key": "ollama",
      "models": ${OLLAMA_MODELS_JSON}
    }
EOF
)
    fi
    if [ "$USE_OPENROUTER" = "true" ]; then
        OR_BLOCK=$(cat <<EOF
    {
      "name": "openrouter",
      "api_base_url": "https://openrouter.ai/api/v1/chat/completions",
      "api_key": "${OPENROUTER_KEY}",
      "models": ${OR_MODELS_JSON},
      "transformer": { "use": ["openrouter"] }
    }
EOF
)
        if [ -n "$PROVIDERS_JSON" ]; then
            PROVIDERS_JSON="${PROVIDERS_JSON},
${OR_BLOCK}"
        else
            PROVIDERS_JSON="$OR_BLOCK"
        fi
    fi

    # Build Router block
    ROUTER_ENTRIES="    \"default\": \"${DEFAULT_PROVIDER},${default_model}\",
    \"background\": \"${DEFAULT_PROVIDER},${background_model}\",
    \"think\": \"${DEFAULT_PROVIDER},${think_model}\""
    if [ "$USE_OPENROUTER" = "true" ] && [ -n "$long_model" ]; then
        ROUTER_ENTRIES="${ROUTER_ENTRIES},
    \"longContext\": \"openrouter,${long_model}\""
    fi
    ROUTER_ENTRIES="${ROUTER_ENTRIES},
    \"longContextThreshold\": 60000"

    printf "%b\n" "${CYAN}Creating configuration file: $CONFIG_FILE${RC}"
    cat > "$CONFIG_FILE" <<EOF
{
  "PORT": 3456,
  "HOST": "127.0.0.1",
  "LOG": true,
  "LOG_LEVEL": "info",
  "API_TIMEOUT_MS": 600000,

  "Providers": [
${PROVIDERS_JSON}
  ],

  "Router": {
${ROUTER_ENTRIES}
  }
}
EOF

    chmod 600 "$CONFIG_FILE"
    printf "%b\n" "${GREEN}Configuration file has been created${RC}"
    printf "%b\n" "${CYAN}Configuration saved to: $CONFIG_FILE${RC}"
    if [ "$USE_OPENROUTER" = "true" ] && [ "$OPENROUTER_KEY" = "\$OPENROUTER_API_KEY" ]; then
        printf "%b\n" "${YELLOW}Remember to export OPENROUTER_API_KEY in your shell${RC}"
    fi
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

    CCR_BIN=$(command -v ccr)
    if [ -z "$CCR_BIN" ]; then
        printf "%b\n" "${RED}ccr not found in PATH, skipping systemd service${RC}"
        return
    fi

    cat > "$SERVICE_FILE" <<EOF
[Unit]
Description=Claude Code Router Service
After=network.target

[Service]
Type=simple
Environment=PATH=${PATH}
ExecStart=${CCR_BIN} server
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

    checkEnv
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
