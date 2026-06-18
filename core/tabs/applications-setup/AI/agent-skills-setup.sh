#!/bin/sh -e

. ../../common-script.sh

# Installs curated agent skills via `npx skills`, targeting all supported agents
# (Claude Code, Copilot, Zed, ...). Each skill is installed globally when the
# repo allows it, and automatically retried at project scope when global is
# rejected — so repos that can't be installed globally still land.
#
# Auth:
#   - GitHub API: reuses your `gh` token (if logged in) to avoid the 60-req/hour
#     unauthenticated rate limit that otherwise makes repo fetches fail.
#   - SSH-only repos (prefixed "ssh:"): use your SSH/gpg agent socket; skipped
#     with a notice if no agent is available.

GITHUB_TOKEN="${GITHUB_TOKEN:-$(gh auth token 2>/dev/null || true)}"
[ -n "$GITHUB_TOKEN" ] && export GITHUB_TOKEN
SSH_SOCK="${SSH_AUTH_SOCK:-$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null || true)}"

INSTALLED=0
FAILED=0
SKIPPED=0
FAILED_LIST=""

# Always restore the cursor, even if interrupted mid-spinner.
trap 'printf "\033[?25h"' EXIT INT TERM

ensureNpx() {
    if command_exists npx; then
        return 0
    fi
    printf "%b\n" "${YELLOW}npx not found — installing Node.js...${RC}"
    case "$PACKAGER" in
        pacman)       "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm nodejs npm ;;
        apt-get|nala) "$ESCALATION_TOOL" "$PACKAGER" install -y nodejs npm ;;
        dnf)          "$ESCALATION_TOOL" "$PACKAGER" install -y nodejs npm ;;
        zypper)       "$ESCALATION_TOOL" "$PACKAGER" install -y nodejs npm ;;
        apk)          "$ESCALATION_TOOL" "$PACKAGER" add nodejs npm ;;
        xbps-install) "$ESCALATION_TOOL" "$PACKAGER" -Sy nodejs ;;
        *)            printf "%b\n" "${RED}Install Node.js manually then re-run.${RC}"; exit 1 ;;
    esac
}

# spin <message> <command...> — run a command silently with an inline spinner.
# Captures combined stdout+stderr in SPIN_OUT; returns the command's exit status.
spin() {
    _msg="$1"; shift
    _log="$(mktemp 2>/dev/null || printf '/tmp/skills.%s' "$$")"
    "$@" >"$_log" 2>&1 &
    _pid=$!
    printf '\033[?25l'
    _i=0
    while kill -0 "$_pid" 2>/dev/null; do
        printf '\r  %b%s%b %s ' "$CYAN" \
            "$(printf '%s' '|/-\' | cut -c $((_i % 4 + 1)))" "$RC" "$_msg"
        _i=$((_i + 1))
        sleep 0.1 2>/dev/null || true
    done
    if wait "$_pid"; then _st=0; else _st=$?; fi
    printf '\033[?25h'
    SPIN_OUT="$(cat "$_log" 2>/dev/null)"
    rm -f "$_log"
    return "$_st"
}

# add_skill <org/repo|ssh:org/repo> [skill|*]
# Tries a global install first; if the repo rejects global, retries at project
# scope. Emits exactly one ✓/✗ line per skill.
add_skill() {
    _src="$1"; _skill="${2:-*}"
    case "$_src" in
        ssh:*)
            _url="git@github.com:${_src#ssh:}.git"
            if [ -z "$SSH_SOCK" ]; then
                printf '  %b-%b %s  %b(no SSH agent — skipped)%b\n' \
                    "$YELLOW" "$RC" "$_src" "$YELLOW" "$RC"
                SKIPPED=$((SKIPPED + 1)); return 0
            fi ;;
        *) _url="$_src" ;;
    esac

    if [ "$_skill" = "*" ]; then
        _label="$_src"
        set -- skills add "$_url" --all
    else
        _label="$_src ($_skill)"
        set -- skills add "$_url" --skill "$_skill" -a '*' -y
    fi

    if spin "$_label  [global]" env SSH_AUTH_SOCK="$SSH_SOCK" npx --yes "$@" -g; then
        printf '\r\033[K  %b✓%b %s  %b[global]%b\n'  "$GREEN" "$RC" "$_label" "$CYAN" "$RC"
        INSTALLED=$((INSTALLED + 1)); return 0
    fi
    if spin "$_label  [project]" env SSH_AUTH_SOCK="$SSH_SOCK" npx --yes "$@"; then
        printf '\r\033[K  %b✓%b %s  %b[project]%b\n' "$GREEN" "$RC" "$_label" "$YELLOW" "$RC"
        INSTALLED=$((INSTALLED + 1)); return 0
    fi

    printf '\r\033[K  %b✗%b %s\n' "$RED" "$RC" "$_label"
    _why="$(printf '%s' "$SPIN_OUT" | grep -iE 'error|fail|denied|not found|rate limit' | tail -1)"
    [ -n "$_why" ] && printf '      %b%s%b\n' "$YELLOW" "$_why" "$RC"
    FAILED=$((FAILED + 1)); FAILED_LIST="$FAILED_LIST $_src"
    return 0
}

checkEnv
checkEscalationTool
ensureNpx

printf "%b\n" "${YELLOW}Installing agent skills (global where supported, else project scope)...${RC}"
[ -z "$GITHUB_TOKEN" ] && \
    printf "%b\n" "${YELLOW}No gh token — GitHub fetches may hit rate limits. Run 'gh auth login'.${RC}"
printf "\n"

# ── skills.sh / public HTTPS repos ────────────────────────────────────────────

# Oliver's own skills
add_skill "TuxLux40/steam-debugger"    "*"
add_skill "TuxLux40/kde-theming-skill" "*"

# Honcho memory platform skills
add_skill "plastic-labs/honcho" "*"

# Anthropic example skills
add_skill "anthropics/skills" "frontend-design"
add_skill "anthropics/skills" "skill-creator"
add_skill "anthropics/skills" "webapp-testing"

# Vercel Labs
add_skill "vercel-labs/agent-browser"  "agent-browser"
add_skill "vercel-labs/agent-skills"   "web-design-guidelines"

# Curated single-skill repos
add_skill "obra/superpowers"       "systematic-debugging"
add_skill "mattpocock/skills"      "triage"
add_skill "squirrelscan/skills"    "audit-website"
add_skill "juliusbrussee/caveman"  "caveman"
add_skill "firecrawl/cli"          "firecrawl-scrape"
add_skill "pbakaus/impeccable"     "distill"

# Mobile / design
add_skill "expo/skills"               "building-native-ui"
add_skill "sleekdotdesign/agent-skills" "sleek-design-mobile-apps"

# Database / backend
add_skill "supabase/agent-skills" "supabase-postgres-best-practices"

# Planning / productivity
add_skill "othmanadi/planning-with-files" "*"

# ── SSH-authenticated repos ────────────────────────────────────────────────────
# These repos require SSH access to GitHub. They will be skipped if no SSH
# agent is available and can be re-run once SSH is set up.

# Accessibility
add_skill "ssh:addyosmani/accessibility"    "*"

# A/B testing
add_skill "ssh:coreyhaines31/ab-testing"    "*"

# File organiser
add_skill "ssh:composiohq/file-organizer"   "*"

# Agent tools meta-skills
add_skill "ssh:qu-skills/agent-tools"       "*"

# Notion — specific skills Oliver researched
add_skill "ssh:notion/agent-skills" "create-database-row"
add_skill "ssh:notion/agent-skills" "database-query"
add_skill "ssh:notion/agent-skills" "find"
add_skill "ssh:notion/agent-skills" "knowledge-capture"
add_skill "ssh:notion/agent-skills" "notion-cli"
add_skill "ssh:notion/agent-skills" "notion-research-documentation"
add_skill "ssh:notion/agent-skills" "spec-to-implementation"
add_skill "ssh:notion/agent-skills" "tasks-setup"

# Cloudflare — specific skills Oliver researched
add_skill "ssh:cloudflare/agent-skills" "agents-sdk"
add_skill "ssh:cloudflare/agent-skills" "building-ai-agent-on-cloudflare"
add_skill "ssh:cloudflare/agent-skills" "building-mcp-server-on-cloudflare"
add_skill "ssh:cloudflare/agent-skills" "cloudflare"
add_skill "ssh:cloudflare/agent-skills" "web-perf"
add_skill "ssh:cloudflare/agent-skills" "wrangler"

printf "\n"
printf "%b\n" "${GREEN}Done: ${INSTALLED} installed, ${FAILED} failed, ${SKIPPED} skipped.${RC}"
[ -n "$FAILED_LIST" ] && printf "%b\n" "${YELLOW}Failed:${FAILED_LIST}${RC}"
printf "%b\n" "${CYAN}Restart your editor (Claude Code, Copilot, Zed) to pick up new skills.${RC}"
[ "$SKIPPED" -gt 0 ] && \
    printf "%b\n" "${YELLOW}SSH-skipped skills: start your SSH/gpg agent, then re-run.${RC}"
