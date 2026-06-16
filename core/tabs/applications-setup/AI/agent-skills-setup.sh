#!/bin/sh -e

. ../../common-script.sh

# Installs agent skills globally via `npx skills add`, targeting all supported
# agents (Claude Code, GitHub Copilot, Zed). SSH-authenticated repos (notion,
# cloudflare, some others) require your SSH agent to be running and authorised
# on GitHub — the script will skip and report those if auth fails.

SSH_SOCK="${SSH_AUTH_SOCK:-$(gpgconf --list-dirs agent-ssh-socket 2>/dev/null || true)}"

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

# Install one or all skills from a GitHub repo.
# Usage: add_skill <org/repo> [skill-name|*]
# Repos that require SSH: prefix org/repo with "ssh:" e.g. "ssh:notion/agent-skills"
add_skill() {
    local src="$1"
    local skill="${2:-*}"
    local url

    case "$src" in
        ssh:*)
            url="git@github.com:${src#ssh:}.git"
            if [ -z "$SSH_SOCK" ]; then
                printf "%b\n" "${YELLOW}Skipping $src — no SSH agent socket found.${RC}"
                return 0
            fi
            ;;
        *)
            url="$src"
            ;;
    esac

    printf "%b\n" "${CYAN}Installing from $src${skill:+ (skill: $skill)}...${RC}"

    if [ "$skill" = "*" ]; then
        SSH_AUTH_SOCK="$SSH_SOCK" npx --yes skills add "$url" --all -g 2>&1 | \
            grep -v "^$" | grep -v "agent-" || true
    else
        SSH_AUTH_SOCK="$SSH_SOCK" npx --yes skills add "$url" \
            --skill "$skill" -g -a '*' -y 2>&1 | \
            grep -v "^$" | grep -v "agent-" || true
    fi
}

checkEnv
checkEscalationTool
ensureNpx

printf "%b\n" "${YELLOW}Installing agent skills globally (Claude Code, Copilot, Zed)...${RC}"

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

printf "%b\n" "${GREEN}Agent skills installation complete.${RC}"
printf "%b\n" "${CYAN}Skills are live in Claude Code and GitHub Copilot. Restart your editor to pick them up.${RC}"
printf "%b\n" "${YELLOW}Note: Grok CLI does not yet have a skills directory supported by 'npx skills'.${RC}"
printf "%b\n" "${YELLOW}Note: SSH-skipped skills can be installed manually: SSH_AUTH_SOCK=\$(gpgconf --list-dirs agent-ssh-socket) npx skills add <repo> --all -g${RC}"
