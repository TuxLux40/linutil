#!/bin/sh -e

. ../common-script.sh

DRY_RUN=${DRY_RUN:-0}

if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
fi

SSHD_CONFIG="/etc/ssh/sshd_config"

run_root() {
    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] $*${RC}"
        return 0
    fi

    "$ESCALATION_TOOL" "$@"
}

update_sshd_option() {
    file=$1
    key=$2
    value=$3
    tmp_file=$(mktemp)

    awk -v key="$key" -v value="$value" '
        BEGIN { done = 0 }
        $0 ~ "^[[:space:]]*#?[[:space:]]*" key "([[:space:]]|$)" && !done {
            print key " " value
            done = 1
            next
        }
        { print }
        END {
            if (!done) {
                print key " " value
            }
        }
    ' "$file" > "$tmp_file"

    mv "$tmp_file" "$file"
}

restart_sshd() {
    if ! command_exists systemctl; then
        return 0
    fi

    if systemctl is-active --quiet sshd; then
        run_root systemctl restart sshd
    elif systemctl is-active --quiet ssh; then
        run_root systemctl restart ssh
    fi
}

show_port_recommendation() {
    if ! grep -Eq '^[[:space:]]*Port[[:space:]]+22([[:space:]]|$)' "$SSHD_CONFIG"; then
        return 0
    fi

    if command_exists systemctl && systemctl is-active --quiet tailscaled; then
        return 0
    fi

    printf "%b\n" "${CYAN}Recommendation: if this host exposes SSH to untrusted networks, consider moving SSH away from port 22 and pairing it with a VPN or tighter firewall rules.${RC}"
}

main() {
    checkEnv

    if ! command_exists sshd || [ ! -f "$SSHD_CONFIG" ]; then
        printf "%b\n" "${YELLOW}sshd is not installed, skipping SSH hardening${RC}"
        exit 0
    fi

    printf "%b\n" "${CYAN}Applying SSH hardening defaults...${RC}"

    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' EXIT HUP INT TERM
    cp "$SSHD_CONFIG" "$tmp_file"

    update_sshd_option "$tmp_file" "AllowTcpForwarding" "no"
    update_sshd_option "$tmp_file" "AllowAgentForwarding" "no"
    update_sshd_option "$tmp_file" "ClientAliveCountMax" "2"
    update_sshd_option "$tmp_file" "MaxAuthTries" "3"
    update_sshd_option "$tmp_file" "MaxSessions" "2"
    update_sshd_option "$tmp_file" "LogLevel" "VERBOSE"
    update_sshd_option "$tmp_file" "TCPKeepAlive" "no"
    update_sshd_option "$tmp_file" "PrintLastLog" "yes"

    if cmp -s "$tmp_file" "$SSHD_CONFIG"; then
        printf "%b\n" "${GREEN}$SSHD_CONFIG already matches the hardened baseline${RC}"
        rm -f "$tmp_file"
        trap - EXIT HUP INT TERM
        show_port_recommendation
        exit 0
    fi

    backup_file="${SSHD_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
    printf "%b\n" "${YELLOW}Backing up $SSHD_CONFIG to $backup_file${RC}"

    if [ "$DRY_RUN" = "1" ]; then
        cat "$tmp_file"
        printf "%b\n" "${CYAN}[DRY RUN] Would validate sshd configuration with: sshd -t${RC}"
        printf "%b\n" "${CYAN}[DRY RUN] Would restart the active SSH service if needed${RC}"
        rm -f "$tmp_file"
        trap - EXIT HUP INT TERM
        exit 0
    fi

    run_root cp "$SSHD_CONFIG" "$backup_file"
    run_root cp "$tmp_file" "$SSHD_CONFIG"
    rm -f "$tmp_file"
    trap - EXIT HUP INT TERM

    if ! run_root sshd -t; then
        printf "%b\n" "${RED}sshd validation failed. Restoring backup.${RC}"
        run_root cp "$backup_file" "$SSHD_CONFIG"
        exit 1
    fi

    restart_sshd
    show_port_recommendation

    printf "%b\n" "${GREEN}SSH hardening complete.${RC}"
}

main
