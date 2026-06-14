#!/bin/sh -e

# Honcho AI Memory Setup
# Installs honcho-cli, configures ~/.honcho/config.json, and optionally
# wires up the Claude Code plugin, skills, MCP server, and agent hooks.

. ../../common-script.sh

HONCHO_CONFIG_DIR="$HOME/.honcho"
HONCHO_CONFIG_FILE="$HONCHO_CONFIG_DIR/config.json"
HONCHO_DEFAULT_URL="https://api.honcho.dev"
CLAUDE_SETTINGS="$HOME/.claude/settings.json"

checkRoot() {
    if [ "$(id -u)" -eq 0 ]; then
        printf "%b\n" "${RED}This script must not be run as root.${RC}"
        exit 1
    fi
}

# ---------------------------------------------------------------------------
# Dependency installers
# ---------------------------------------------------------------------------

ensureUv() {
    if command_exists uv; then
        printf "%b\n" "${GREEN}uv is already installed: $(uv --version)${RC}"
        return 0
    fi
    printf "%b\n" "${CYAN}Installing uv (Python package manager)...${RC}"
    curl -LsSf https://astral.sh/uv/install.sh | sh
    # Add to current PATH so subsequent commands can find it
    export PATH="$HOME/.cargo/bin:$HOME/.local/bin:$PATH"
    if ! command_exists uv; then
        printf "%b\n" "${RED}uv installation failed. Please install manually: https://docs.astral.sh/uv/${RC}"
        exit 1
    fi
    printf "%b\n" "${GREEN}uv installed: $(uv --version)${RC}"
}

ensureBun() {
    if command_exists bun; then
        printf "%b\n" "${GREEN}bun is already installed: $(bun --version)${RC}"
        return 0
    fi
    printf "%b\n" "${CYAN}Installing bun (required for Claude Code hooks)...${RC}"
    curl -fsSL https://bun.sh/install | bash
    export PATH="$HOME/.bun/bin:$PATH"
    # Also persist to fish config if present
    if [ -f "$HOME/.config/fish/config.fish" ]; then
        if ! grep -q "bun" "$HOME/.config/fish/config.fish" 2>/dev/null; then
            printf '\nfish_add_path ~/.bun/bin\n' >> "$HOME/.config/fish/config.fish"
        fi
    fi
    if ! command_exists bun; then
        printf "%b\n" "${YELLOW}bun not found in PATH yet — you may need to restart your shell.${RC}"
        printf "%b\n" "${YELLOW}Claude Code hooks require bun. Add ~/.bun/bin to your PATH.${RC}"
    else
        printf "%b\n" "${GREEN}bun installed: $(bun --version)${RC}"
    fi
}

ensureJq() {
    if command_exists jq; then
        return 0
    fi
    printf "%b\n" "${CYAN}Installing jq...${RC}"
    case "$PACKAGER" in
        pacman) "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm jq ;;
        apt-get | nala) "$ESCALATION_TOOL" "$PACKAGER" install -y jq ;;
        dnf | yum) "$ESCALATION_TOOL" "$PACKAGER" install -y jq ;;
        zypper) "$ESCALATION_TOOL" "$PACKAGER" install -y jq ;;
        apk) "$ESCALATION_TOOL" "$PACKAGER" add jq ;;
        xbps-install) "$ESCALATION_TOOL" "$PACKAGER" -Sy jq ;;
        *) printf "%b\n" "${YELLOW}jq not found and package manager unknown — install jq manually.${RC}" ;;
    esac
}

# ---------------------------------------------------------------------------
# Install honcho-cli
# ---------------------------------------------------------------------------

installHonchoCli() {
    printf "%b\n" "${CYAN}Checking Honcho CLI...${RC}"
    if command_exists honcho; then
        printf "%b\n" "${GREEN}honcho CLI is already installed.${RC}"
        printf "%b" "${YELLOW}Update to latest? [y/N] ${RC}"
        read -r do_update
        case "$do_update" in
            y | Y)
                printf "%b\n" "${CYAN}Updating honcho-cli...${RC}"
                uv tool upgrade honcho-cli 2>/dev/null || uv tool install --upgrade honcho-cli
                printf "%b\n" "${GREEN}honcho-cli updated.${RC}"
                ;;
            *) printf "%b\n" "${CYAN}Skipping update.${RC}" ;;
        esac
    else
        printf "%b\n" "${CYAN}Installing honcho-cli...${RC}"
        uv tool install honcho-cli
        export PATH="$HOME/.local/bin:$PATH"
        if ! command_exists honcho; then
            printf "%b\n" "${YELLOW}honcho not found in PATH yet. Trying pipx fallback...${RC}"
            if command_exists pipx; then
                pipx install honcho-cli
            else
                printf "%b\n" "${RED}Could not install honcho-cli. Make sure uv or pipx is on PATH.${RC}"
                exit 1
            fi
        fi
        printf "%b\n" "${GREEN}honcho-cli installed.${RC}"
    fi
}

# ---------------------------------------------------------------------------
# Interactive config wizard
# ---------------------------------------------------------------------------

promptSecret() {
    # Read a value without echoing to terminal
    prompt="$1"
    printf "%b" "$prompt"
    stty -echo 2>/dev/null || true
    read -r secret_val
    stty echo 2>/dev/null || true
    printf "\n"
    echo "$secret_val"
}

configureHoncho() {
    printf "\n"
    printf "%b\n" "${CYAN}--- Honcho Configuration ---${RC}"

    # API key
    printf "%b\n" "${CYAN}Get your API key at https://app.honcho.dev under 'API KEYS'${RC}"
    api_key=$(promptSecret "${YELLOW}API key: ${RC}")
    if [ -z "$api_key" ]; then
        printf "%b\n" "${RED}API key is required.${RC}"
        exit 1
    fi

    # Base URL
    printf "%b" "${YELLOW}Honcho API URL [${HONCHO_DEFAULT_URL}]: ${RC}"
    read -r base_url
    base_url="${base_url:-$HONCHO_DEFAULT_URL}"

    # Workspace
    printf "%b" "${YELLOW}Workspace name [main]: ${RC}"
    read -r workspace
    workspace="${workspace:-main}"

    # Peer name
    printf "%b" "${YELLOW}Your peer name [${USER:-oliver}]: ${RC}"
    read -r peer_name
    peer_name="${peer_name:-${USER:-oliver}}"

    # Write ~/.honcho/config.json
    mkdir -p "$HONCHO_CONFIG_DIR"
    cat > "$HONCHO_CONFIG_FILE" <<EOF
{
  "apiKey": "${api_key}",
  "peerName": "${peer_name}",
  "environmentUrl": "${base_url}",
  "hosts": {
    "claude_code": {
      "workspace": "${workspace}",
      "aiPeer": "claude",
      "enabled": true,
      "logging": true,
      "saveMessages": true
    }
  }
}
EOF
    chmod 600 "$HONCHO_CONFIG_FILE"
    printf "%b\n" "${GREEN}Config written to ${HONCHO_CONFIG_FILE}${RC}"

    # Register with honcho CLI
    if command_exists honcho; then
        printf "%b\n" "${CYAN}Registering API key with honcho CLI...${RC}"
        honcho init --api-key "$api_key" --base-url "$base_url" 2>/dev/null || true
        printf "%b\n" "${GREEN}honcho CLI configured.${RC}"
    fi
}

# ---------------------------------------------------------------------------
# Claude Code integration
# ---------------------------------------------------------------------------

installClaudePlugin() {
    printf "\n"
    printf "%b\n" "${CYAN}--- Claude Code Plugin ---${RC}"
    printf "%b\n" "${CYAN}The honcho plugin adds persistent memory hooks to every Claude Code session${RC}"
    printf "%b\n" "${CYAN}(SessionStart/Stop/UserPrompt/PostToolUse/PreCompact). Requires bun.${RC}"
    printf "%b" "${YELLOW}Set up the honcho Claude Code plugin? [Y/n] ${RC}"
    read -r want_plugin
    case "$want_plugin" in
        n | N) return 0 ;;
    esac

    ensureBun

    mkdir -p "$HOME/.claude"
    if [ ! -f "$CLAUDE_SETTINGS" ]; then
        printf '{"theme":"dark"}\n' > "$CLAUDE_SETTINGS"
    fi

    # Step 1: Register the marketplace in settings.json so Claude Code can find the plugin
    if command_exists jq; then
        MARKETPLACE_ENTRY='{"source":{"source":"github","repo":"plastic-labs/claude-honcho"}}'
        if ! jq -e '.extraKnownMarketplaces.honcho' "$CLAUDE_SETTINGS" > /dev/null 2>&1; then
            jq --argjson m "$MARKETPLACE_ENTRY" \
                '.extraKnownMarketplaces = (.extraKnownMarketplaces // {}) + {"honcho": $m}' \
                "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
            printf "%b\n" "${GREEN}Honcho marketplace registered in settings.json.${RC}"
        else
            printf "%b\n" "${CYAN}Marketplace already registered.${RC}"
        fi
    fi

    # Step 2: Try automatic install via claude CLI
    if command_exists claude; then
        printf "%b\n" "${CYAN}Installing plugin via Claude Code CLI...${RC}"
        if claude plugin install honcho@honcho 2>/dev/null; then
            printf "%b\n" "${GREEN}Plugin installed automatically.${RC}"
            setupStatusline
            return 0
        fi
        printf "%b\n" "${YELLOW}Automatic install failed (plugin manager may require interactive session).${RC}"
    fi

    # Step 3: Inform user of in-Claude commands needed
    printf "\n"
    printf "%b\n" "${YELLOW}Complete plugin install inside Claude Code by running:${RC}"
    printf "%b\n" "${CYAN}  /plugin marketplace add plastic-labs/claude-honcho${RC}"
    printf "%b\n" "${CYAN}  /plugin install honcho@honcho${RC}"
    printf "%b\n" "${CYAN}  /reload-plugins${RC}"
    printf "\n"
}

setupStatusline() {
    STATUSLINE_SH="$HONCHO_CONFIG_DIR/honcho-statusline.sh"
    PLUGIN_CACHE="$HOME/.claude/plugins/cache/honcho/honcho"
    PLUGIN_VER_DIR=$(find "$PLUGIN_CACHE" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | sort -V | tail -1)

    if [ -n "$PLUGIN_VER_DIR" ] && [ -f "$PLUGIN_VER_DIR/scripts/honcho-statusline.sh" ]; then
        cp "$PLUGIN_VER_DIR/scripts/honcho-statusline.sh" "$STATUSLINE_SH"
        chmod 755 "$STATUSLINE_SH"

        if command_exists jq && [ -f "$CLAUDE_SETTINGS" ]; then
            if ! jq -e '.statusLine' "$CLAUDE_SETTINGS" > /dev/null 2>&1; then
                jq --arg cmd "$STATUSLINE_SH" \
                    '. + {"statusLine":{"type":"command","command":$cmd,"refreshInterval":1}}' \
                    "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
                printf "%b\n" "${GREEN}Honcho statusline registered.${RC}"
            else
                printf "%b\n" "${YELLOW}Existing statusLine — not overwriting.${RC}"
            fi
        fi
    fi
}

installClaudeSkills() {
    printf "\n"
    printf "%b\n" "${CYAN}--- Claude Code Skills ---${RC}"
    printf "%b\n" "${CYAN}Available: honcho-cli (workspace inspection) + honcho-integration (SDK wiring)${RC}"
    printf "%b" "${YELLOW}Install honcho skills for Claude Code? [Y/n] ${RC}"
    read -r want_skills
    case "$want_skills" in
        n | N) return 0 ;;
    esac

    if ! command_exists npx; then
        printf "%b\n" "${YELLOW}npx not found — skipping skill install. Install Node.js first.${RC}"
        return 0
    fi

    printf "%b\n" "${CYAN}Installing honcho-cli skill...${RC}"
    npx skills add plastic-labs/claude-honcho@honcho-cli -g -y 2>/dev/null && \
        printf "%b\n" "${GREEN}honcho-cli skill installed.${RC}" || \
        printf "%b\n" "${YELLOW}honcho-cli skill install failed (may need manual install).${RC}"

    printf "%b\n" "${CYAN}Installing honcho-integration skill...${RC}"
    npx skills add plastic-labs/claude-honcho@honcho-integration -g -y 2>/dev/null && \
        printf "%b\n" "${GREEN}honcho-integration skill installed.${RC}" || \
        printf "%b\n" "${YELLOW}honcho-integration skill install failed.${RC}"
}

installMCPServer() {
    printf "\n"
    printf "%b\n" "${CYAN}--- Honcho MCP Server ---${RC}"
    printf "%b\n" "${CYAN}Connects to the hosted MCP server at https://mcp.honcho.dev${RC}"
    printf "%b\n" "${CYAN}Exposes workspace/peer/session/conclusion tools directly in Claude Code.${RC}"
    printf "%b" "${YELLOW}Register honcho MCP server? [y/N] ${RC}"
    read -r want_mcp
    case "$want_mcp" in
        y | Y) ;;
        *) return 0 ;;
    esac

    # Retrieve values from existing config
    MCP_API_KEY=""
    MCP_PEER_NAME="${USER:-oliver}"
    if command_exists jq && [ -f "$HONCHO_CONFIG_FILE" ]; then
        MCP_API_KEY=$(jq -r '.apiKey // empty' "$HONCHO_CONFIG_FILE" 2>/dev/null)
        MCP_PEER_NAME=$(jq -r '.peerName // empty' "$HONCHO_CONFIG_FILE" 2>/dev/null)
        MCP_PEER_NAME="${MCP_PEER_NAME:-${USER:-oliver}}"
    fi

    if [ -z "$MCP_API_KEY" ]; then
        printf "%b" "${YELLOW}API key (leave blank to use \$HONCHO_API_KEY env var): ${RC}"
        MCP_API_KEY=$(promptSecret "")
    fi

    MCP_URL="https://mcp.honcho.dev"

    if command_exists claude; then
        printf "%b\n" "${CYAN}Registering via Claude Code CLI...${RC}"
        claude mcp add honcho --transport http --url "$MCP_URL" \
            --header "Authorization: Bearer ${MCP_API_KEY}" \
            --header "X-Honcho-User-Name: ${MCP_PEER_NAME}" 2>/dev/null && \
            printf "%b\n" "${GREEN}Honcho MCP server registered via claude CLI.${RC}" && return 0
        printf "%b\n" "${YELLOW}claude mcp add failed — falling back to manual settings.json edit.${RC}"
    fi

    mkdir -p "$HOME/.claude"
    if [ ! -f "$CLAUDE_SETTINGS" ]; then
        printf '{"theme":"dark"}\n' > "$CLAUDE_SETTINGS"
    fi

    if command_exists jq; then
        if jq -e '.mcpServers.honcho' "$CLAUDE_SETTINGS" > /dev/null 2>&1; then
            printf "%b\n" "${YELLOW}honcho MCP server already registered.${RC}"
            return 0
        fi
        jq --arg url "$MCP_URL" \
           --arg auth "Bearer ${MCP_API_KEY}" \
           --arg user "$MCP_PEER_NAME" \
           '.mcpServers = (.mcpServers // {}) + {
               "honcho": {
                   "type": "http",
                   "url": $url,
                   "headers": {
                       "Authorization": $auth,
                       "X-Honcho-User-Name": $user
                   }
               }
           }' \
           "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
        printf "%b\n" "${GREEN}Honcho MCP server registered in ~/.claude/settings.json${RC}"
    else
        printf "%b\n" "${YELLOW}jq not available — add this to ~/.claude/settings.json manually:${RC}"
        printf "%b\n" "${CYAN}  \"mcpServers\": { \"honcho\": { \"type\": \"http\", \"url\": \"${MCP_URL}\",${RC}"
        printf "%b\n" "${CYAN}    \"headers\": { \"Authorization\": \"Bearer ${MCP_API_KEY}\", \"X-Honcho-User-Name\": \"${MCP_PEER_NAME}\" } } }${RC}"
    fi
}

setupAgentHooks() {
    printf "\n"
    printf "%b\n" "${CYAN}--- Agent Hooks (standalone, without plugin) ---${RC}"
    printf "%b\n" "${CYAN}Adds honcho memory hooks directly to ~/.claude/settings.json.${RC}"
    printf "%b\n" "${CYAN}Skip this if you installed the Claude Code plugin — hooks are already included.${RC}"
    printf "%b" "${YELLOW}Set up standalone agent hooks? [y/N] ${RC}"
    read -r want_hooks
    case "$want_hooks" in
        y | Y) ;;
        *) return 0 ;;
    esac

    ensureBun

    PLUGIN_CACHE="$HOME/.claude/plugins/cache/honcho/honcho"
    if [ ! -d "$PLUGIN_CACHE" ]; then
        printf "%b\n" "${RED}Plugin directory not found — cannot set up hooks without the plugin files.${RC}"
        printf "%b\n" "${YELLOW}Install the Claude Code plugin first, then re-run this step.${RC}"
        return 0
    fi

    PLUGIN_VER_DIR=$(find "$PLUGIN_CACHE" -maxdepth 1 -mindepth 1 -type d | sort -V | tail -1)
    BUN_BIN=$(command -v bun 2>/dev/null || echo "$HOME/.bun/bin/bun")

    mkdir -p "$HOME/.claude"
    if [ ! -f "$CLAUDE_SETTINGS" ]; then
        printf '{"theme":"dark"}\n' > "$CLAUDE_SETTINGS"
    fi

    if ! command_exists jq; then
        printf "%b\n" "${YELLOW}jq required for hook setup — skipping.${RC}"
        return 0
    fi

    # Merge hooks into settings.json using jq
    HOOKS_JSON=$(cat <<EOF
{
  "UserPromptSubmit":[{"hooks":[{"type":"command","command":"${BUN_BIN} run ${PLUGIN_VER_DIR}/hooks/user-prompt.ts","timeout":7000}]}],
  "Stop":[{"hooks":[{"type":"command","command":"${BUN_BIN} run ${PLUGIN_VER_DIR}/hooks/stop.ts","timeout":10000}]}],
  "PostToolUse":[{"matcher":"Write|Edit|Bash|Task","hooks":[{"type":"command","command":"${BUN_BIN} run ${PLUGIN_VER_DIR}/hooks/post-tool-use.ts","timeout":10000}]}],
  "PreCompact":[{"matcher":"auto","hooks":[{"type":"command","command":"${BUN_BIN} run ${PLUGIN_VER_DIR}/hooks/pre-compact.ts","timeout":20000}]},{"matcher":"manual","hooks":[{"type":"command","command":"${BUN_BIN} run ${PLUGIN_VER_DIR}/hooks/pre-compact.ts","timeout":20000}]}],
  "SessionStart":[{"hooks":[{"type":"command","command":"${BUN_BIN} run ${PLUGIN_VER_DIR}/hooks/session-start.ts","timeout":30000,"async":true}]}],
  "SessionEnd":[{"hooks":[{"type":"command","command":"${BUN_BIN} run ${PLUGIN_VER_DIR}/hooks/session-end.ts","timeout":30000}]}]
}
EOF
)

    jq --argjson h "$HOOKS_JSON" '.hooks = (.hooks // {}) * $h' \
        "$CLAUDE_SETTINGS" > "${CLAUDE_SETTINGS}.tmp" && mv "${CLAUDE_SETTINGS}.tmp" "$CLAUDE_SETTINGS"
    setupStatusline
    printf "%b\n" "${GREEN}Agent hooks registered in ~/.claude/settings.json${RC}"
    printf "%b\n" "${YELLOW}Restart Claude Code for hooks to take effect.${RC}"
}

# ---------------------------------------------------------------------------
# VS Code / GitHub Copilot integration
# ---------------------------------------------------------------------------

setupVSCodeCopilot() {
    printf "\n"
    printf "%b\n" "${CYAN}--- VS Code / GitHub Copilot ---${RC}"
    printf "%b\n" "${CYAN}Registers Honcho as an MCP server in VS Code user settings.${RC}"

    # Resolve API key and peer name from honcho config
    VS_API_KEY=""
    VS_PEER_NAME="${USER:-oliver}"
    if command_exists jq && [ -f "$HONCHO_CONFIG_FILE" ]; then
        VS_API_KEY=$(jq -r '.apiKey // empty' "$HONCHO_CONFIG_FILE" 2>/dev/null)
        VS_PEER_NAME=$(jq -r '.peerName // empty' "$HONCHO_CONFIG_FILE" 2>/dev/null)
        VS_PEER_NAME="${VS_PEER_NAME:-${USER:-oliver}}"
    fi

    # VS Code user settings path (cross-platform)
    case "$(uname -s)" in
        Darwin) VSCODE_SETTINGS="$HOME/Library/Application Support/Code/User/settings.json" ;;
        *)       VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json" ;;
    esac

    if [ ! -f "$VSCODE_SETTINGS" ]; then
        printf "%b\n" "${YELLOW}VS Code settings not found at ${VSCODE_SETTINGS}${RC}"
        printf "%b\n" "${YELLOW}If VS Code is installed elsewhere, add this to your user settings.json:${RC}"
        printf "%b\n" "${CYAN}  \"mcp\": { \"servers\": { \"honcho\": { \"type\": \"http\",${RC}"
        printf "%b\n" "${CYAN}    \"url\": \"https://mcp.honcho.dev\",${RC}"
        printf "%b\n" "${CYAN}    \"headers\": { \"Authorization\": \"Bearer ${VS_API_KEY}\", \"X-Honcho-User-Name\": \"${VS_PEER_NAME}\" } } } }${RC}"
        return 0
    fi

    if ! command_exists jq; then
        printf "%b\n" "${YELLOW}jq required — skipping VS Code setup.${RC}"
        return 0
    fi

    if jq -e '.mcp.servers.honcho' "$VSCODE_SETTINGS" > /dev/null 2>&1; then
        printf "%b\n" "${YELLOW}honcho already registered in VS Code settings.${RC}"
        return 0
    fi

    jq --arg key "$VS_API_KEY" --arg user "$VS_PEER_NAME" \
        '.mcp = (.mcp // {}) | .mcp.servers = (.mcp.servers // {}) + {
            "honcho": {
                "type": "http",
                "url": "https://mcp.honcho.dev",
                "headers": {
                    "Authorization": ("Bearer " + $key),
                    "X-Honcho-User-Name": $user
                }
            }
        }' \
        "$VSCODE_SETTINGS" > "${VSCODE_SETTINGS}.tmp" && mv "${VSCODE_SETTINGS}.tmp" "$VSCODE_SETTINGS"
    printf "%b\n" "${GREEN}Honcho registered in VS Code settings. Reload VS Code to activate.${RC}"
}

# ---------------------------------------------------------------------------
# Grok / xAI peer setup
# ---------------------------------------------------------------------------

setupGrokPeer() {
    printf "\n"
    printf "%b\n" "${CYAN}--- Grok / xAI ---${RC}"
    printf "%b\n" "${CYAN}xAI does not support MCP. Grok integrates with Honcho via the Python/TS SDK.${RC}"

    GR_WORKSPACE="main"
    if command_exists jq && [ -f "$HONCHO_CONFIG_FILE" ]; then
        GR_WORKSPACE=$(jq -r '.hosts.claude_code.workspace // "main"' "$HONCHO_CONFIG_FILE" 2>/dev/null)
    fi

    if ! command_exists honcho; then
        printf "%b\n" "${YELLOW}honcho CLI not in PATH — peer will be created automatically on first SDK call.${RC}"
        return 0
    fi

    if honcho peer inspect grok -w "$GR_WORKSPACE" --json > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ 'grok' peer already exists in workspace '${GR_WORKSPACE}'.${RC}"
    else
        printf "%b\n" "${CYAN}Peer 'grok' not yet in workspace — it is created automatically${RC}"
        printf "%b\n" "${CYAN}on the first Honcho SDK call from your xAI agent.${RC}"
    fi

    printf "\n"
    printf "%b\n" "${CYAN}Initialise the Honcho SDK client with:${RC}"
    printf "%b\n" "${CYAN}  peer_name = \"grok\"${RC}"
    printf "%b\n" "${CYAN}  user_name = \"${USER:-oliver}\"${RC}"
    printf "%b\n" "${CYAN}  workspace_id = \"${GR_WORKSPACE}\"${RC}"
    printf "%b\n" "${CYAN}See: https://honcho.dev/docs/v3/documentation/introduction/quickstart${RC}"
}

# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

validateSetup() {
    printf "\n"
    printf "%b\n" "${CYAN}--- Validating ---${RC}"

    if command_exists honcho; then
        if honcho workspace inspect -w main --json > /dev/null 2>&1; then
            printf "%b\n" "${GREEN}✓ honcho CLI connected to workspace.${RC}"
        else
            printf "%b\n" "${YELLOW}⚠ honcho CLI installed but connection failed — check your API key.${RC}"
        fi
    else
        printf "%b\n" "${YELLOW}⚠ honcho command not found in PATH (may need shell restart).${RC}"
    fi

    if [ -f "$HONCHO_CONFIG_FILE" ]; then
        printf "%b\n" "${GREEN}✓ Config: ${HONCHO_CONFIG_FILE}${RC}"
    fi

    if command_exists bun || [ -x "$HOME/.bun/bin/bun" ]; then
        printf "%b\n" "${GREEN}✓ bun is available (Claude Code hooks ready).${RC}"
    else
        printf "%b\n" "${YELLOW}⚠ bun not found — Claude Code hooks will fail until installed.${RC}"
    fi
}

# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

main() {
    printf "\n"
    printf "%b\n" "${CYAN}============================================${RC}"
    printf "%b\n" "${CYAN}          Honcho AI Memory Setup            ${RC}"
    printf "%b\n" "${CYAN}============================================${RC}"
    printf "\n"

    checkEnv
    checkRoot

    # Core: uv + honcho-cli + config
    ensureUv
    ensureJq
    installHonchoCli
    configureHoncho

    # Optional: Claude Code integrations
    if command_exists claude || [ -d "$HOME/.claude" ]; then
        printf "\n"
        printf "%b\n" "${CYAN}Claude Code detected. Setting up integrations...${RC}"
        installClaudePlugin
        installClaudeSkills
        installMCPServer
        setupAgentHooks
    else
        printf "\n"
        printf "%b\n" "${YELLOW}Claude Code not detected.${RC}"
        printf "%b" "${YELLOW}Set up Claude Code integrations anyway? [y/N] ${RC}"
        read -r force_claude
        case "$force_claude" in
            y | Y)
                installClaudePlugin
                installClaudeSkills
                installMCPServer
                setupAgentHooks
                ;;
        esac
    fi

    # Other agents
    setupVSCodeCopilot
    setupGrokPeer

    validateSetup

    printf "\n"
    printf "%b\n" "${GREEN}✓ Honcho setup complete!${RC}"
    printf "\n"
    printf "%b\n" "${CYAN}Next steps:${RC}"
    printf "%b\n" "${CYAN}  honcho workspace inspect -w main     — verify workspace${RC}"
    printf "%b\n" "${CYAN}  honcho peer card oliver               — view your memory${RC}"
    printf "%b\n" "${CYAN}  Restart Claude Code / VS Code / Cursor to activate${RC}"
    printf "\n"
}

main "$@"
