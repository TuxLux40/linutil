#!/bin/sh -e

. ../common-script.sh

NFTABLES_CONF=/etc/nftables.conf

requireNft() {
    checkCommandRequirements "nft awk grep"
}

ensureConfigPresent() {
    if [ ! -f "$NFTABLES_CONF" ]; then
        printf "%b\n" "${RED}Missing ${NFTABLES_CONF}. Cannot patch safely.${RC}"
        exit 1
    fi
}

backupConfig() {
    BACKUP_PATH="/etc/nftables.conf.linutil-bak.$(date +%Y%m%d-%H%M%S)"
    printf "%b\n" "${YELLOW}Backing up ${NFTABLES_CONF} to ${BACKUP_PATH}${RC}"
    "$ESCALATION_TOOL" cp "$NFTABLES_CONF" "$BACKUP_PATH"
}

configHasForwardingRules() {
    grep -q 'iifname "tailscale0" accept comment "forward from tailnet"' "$NFTABLES_CONF" &&
        grep -q 'oifname "tailscale0" accept comment "forward to tailnet"' "$NFTABLES_CONF"
}

patchConfig() {
    TMP_FILE=$("$ESCALATION_TOOL" mktemp /tmp/linutil-nftables.XXXXXX)

    "$ESCALATION_TOOL" awk '
        BEGIN { in_forward=0; inserted=0 }
        {
            print
            if ($0 ~ /^[[:space:]]*chain forward[[:space:]]*\{[[:space:]]*$/) {
                in_forward=1
                next
            }
            if (in_forward && $0 ~ /^[[:space:]]*policy[[:space:]]+drop[[:space:]]*$/ && inserted==0) {
                print ""
                print "    ct state {established, related} accept comment \"allow forwarded return traffic\""
                print ""
                print "    # Required for Tailscale exit node + subnet routing"
                print "    iifname \"tailscale0\" accept comment \"forward from tailnet\""
                print "    oifname \"tailscale0\" accept comment \"forward to tailnet\""
                inserted=1
            }
            if (in_forward && $0 ~ /^[[:space:]]*}/) {
                in_forward=0
            }
        }
        END {
            if (inserted==0) {
                exit 2
            }
        }
    ' "$NFTABLES_CONF" | "$ESCALATION_TOOL" tee "$TMP_FILE" >/dev/null

    if ! "$ESCALATION_TOOL" nft -c -f "$TMP_FILE" >/dev/null 2>&1; then
        printf "%b\n" "${RED}Patched nftables config failed syntax check. Aborting.${RC}"
        "$ESCALATION_TOOL" rm -f "$TMP_FILE"
        exit 1
    fi

    "$ESCALATION_TOOL" cp "$TMP_FILE" "$NFTABLES_CONF"
    "$ESCALATION_TOOL" rm -f "$TMP_FILE"
}

reloadRules() {
    printf "%b\n" "${YELLOW}Reloading nftables rules${RC}"
    "$ESCALATION_TOOL" nft -f "$NFTABLES_CONF"
}

verifyForwardChain() {
    printf "%b\n" "${YELLOW}Verifying inet filter forward chain${RC}"
    "$ESCALATION_TOOL" nft list chain inet filter forward
}

checkEnv
checkEscalationTool
requireNft
ensureConfigPresent

if configHasForwardingRules; then
    printf "%b\n" "${CYAN}Tailscale forward rules already present in ${NFTABLES_CONF}${RC}"
else
    backupConfig
    patchConfig
fi

reloadRules
verifyForwardChain

printf "%b\n" "${GREEN}Tailscale exit-node forwarding patch applied.${RC}"
