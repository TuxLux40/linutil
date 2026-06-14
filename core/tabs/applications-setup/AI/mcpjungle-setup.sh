#!/bin/sh -e

. "$(dirname "$0")/honcho-setup.sh"

JUNGLE_URL=""
JUNGLE_TOKEN=""

promptUrl() {
    printf "%b" "${CYAN}MCP Jungle URL [http://localhost:8080/mcp]: ${RC}"
    read -r JUNGLE_URL
    JUNGLE_URL="${JUNGLE_URL:-http://localhost:8080/mcp}"
}

promptToken() {
    printf "%b\n" "${CYAN}Auth token (leave blank for open/unauthenticated mode):${RC}"
    JUNGLE_TOKEN=$(promptSecret "Token: ")
}

setupClaudeCode() {
    printf "%b\n" "${YELLOW}Configuring Claude Code...${RC}"

    if command_exists claude; then
        if claude mcp list 2>/dev/null | grep -q "mcpjungle"; then
            printf "%b\n" "${GREEN}Claude Code: mcpjungle already registered.${RC}"
            return 0
        fi
        if [ -n "$JUNGLE_TOKEN" ]; then
            if claude mcp add mcpjungle --scope user --transport http "$JUNGLE_URL" \
                    --header "Authorization: Bearer $JUNGLE_TOKEN" 2>/dev/null; then
                printf "%b\n" "${GREEN}Claude Code: mcpjungle registered via CLI.${RC}"
                return 0
            fi
        else
            if claude mcp add mcpjungle --scope user --transport http "$JUNGLE_URL" 2>/dev/null; then
                printf "%b\n" "${GREEN}Claude Code: mcpjungle registered via CLI.${RC}"
                return 0
            fi
        fi
        printf "%b\n" "${YELLOW}claude mcp add failed — falling back to ~/.claude.json.${RC}"
    fi

    CLAUDE_JSON="$HOME/.claude.json"
    TMP=$(mktemp)
    if [ -f "$CLAUDE_JSON" ]; then
        if jq -e '.mcpServers.mcpjungle' "$CLAUDE_JSON" > /dev/null 2>&1; then
            printf "%b\n" "${GREEN}Claude Code: mcpjungle already in ~/.claude.json.${RC}"
            return 0
        fi
        if [ -n "$JUNGLE_TOKEN" ]; then
            jq --arg url "$JUNGLE_URL" --arg tok "$JUNGLE_TOKEN" \
                '.mcpServers = (.mcpServers // {}) + {"mcpjungle": {"type":"http","url":$url,"headers":{"Authorization":("Bearer " + $tok)}}}' \
                "$CLAUDE_JSON" > "$TMP" && mv "$TMP" "$CLAUDE_JSON"
        else
            jq --arg url "$JUNGLE_URL" \
                '.mcpServers = (.mcpServers // {}) + {"mcpjungle": {"type":"http","url":$url}}' \
                "$CLAUDE_JSON" > "$TMP" && mv "$TMP" "$CLAUDE_JSON"
        fi
    else
        if [ -n "$JUNGLE_TOKEN" ]; then
            jq -n --arg url "$JUNGLE_URL" --arg tok "$JUNGLE_TOKEN" \
                '{"mcpServers":{"mcpjungle":{"type":"http","url":$url,"headers":{"Authorization":("Bearer " + $tok)}}}}' \
                > "$CLAUDE_JSON"
        else
            jq -n --arg url "$JUNGLE_URL" \
                '{"mcpServers":{"mcpjungle":{"type":"http","url":$url}}}' \
                > "$CLAUDE_JSON"
        fi
    fi
    printf "%b\n" "${GREEN}Claude Code: mcpjungle written to ~/.claude.json.${RC}"
}

setupVSCode() {
    printf "%b\n" "${YELLOW}Configuring VS Code / Copilot...${RC}"

    VSCODE_SETTINGS="$HOME/.config/Code/User/settings.json"
    if [ ! -f "$VSCODE_SETTINGS" ]; then
        printf "%b\n" "${YELLOW}VS Code settings not found — skipping.${RC}"
        return 0
    fi

    if jq -e '.mcp.servers.mcpjungle' "$VSCODE_SETTINGS" > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}VS Code: mcpjungle already configured.${RC}"
        return 0
    fi

    TMP=$(mktemp)
    if [ -n "$JUNGLE_TOKEN" ]; then
        jq --arg url "$JUNGLE_URL" --arg tok "$JUNGLE_TOKEN" \
            '.mcp.servers.mcpjungle = {"url":$url,"headers":{"Authorization":("Bearer " + $tok)}}' \
            "$VSCODE_SETTINGS" > "$TMP" && mv "$TMP" "$VSCODE_SETTINGS"
    else
        jq --arg url "$JUNGLE_URL" \
            '.mcp.servers.mcpjungle = {"url":$url}' \
            "$VSCODE_SETTINGS" > "$TMP" && mv "$TMP" "$VSCODE_SETTINGS"
    fi
    printf "%b\n" "${GREEN}VS Code: mcpjungle written to settings.json.${RC}"
}

main() {
    checkRoot
    checkEnv
    checkEscalationTool
    ensureJq
    promptUrl
    promptToken
    setupClaudeCode
    setupVSCode
    printf "%b\n" "${YELLOW}Grok/xAI does not support MCP — no action taken.${RC}"
    printf "%b\n" "${GREEN}Done. Restart your agent/editor to pick up the new MCP server.${RC}"
}

main
