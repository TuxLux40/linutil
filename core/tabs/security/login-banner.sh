#!/bin/sh -e

. ../common-script.sh

DRY_RUN=${DRY_RUN:-0}

if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
fi

ISSUE_FILE="/etc/issue"
ISSUE_NET_FILE="/etc/issue.net"
NOTICE_LINE="NOTICE: This system is for authorized use only."

run_root() {
    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] $*${RC}"
        return 0
    fi

    "$ESCALATION_TOOL" "$@"
}

write_if_changed() {
    source_file=$1
    destination_file=$2

    if [ -f "$destination_file" ] && cmp -s "$source_file" "$destination_file"; then
        printf "%b\n" "${GREEN}$destination_file already matches the hardened banner${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Writing $destination_file${RC}"

    if [ "$DRY_RUN" = "1" ]; then
        cat "$source_file"
        return 0
    fi

    run_root cp "$source_file" "$destination_file"
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

configure_ssh_banner() {
    if ! command_exists sshd || [ ! -f /etc/ssh/sshd_config ]; then
        return 0
    fi

    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' EXIT HUP INT TERM
    cp /etc/ssh/sshd_config "$tmp_file"
    update_sshd_option "$tmp_file" "Banner" "$ISSUE_NET_FILE"

    if cmp -s "$tmp_file" /etc/ssh/sshd_config; then
        rm -f "$tmp_file"
        trap - EXIT HUP INT TERM
        return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        cat "$tmp_file"
        printf "%b\n" "${CYAN}[DRY RUN] Would validate sshd configuration with: sshd -t${RC}"
        rm -f "$tmp_file"
        trap - EXIT HUP INT TERM
        return 0
    fi

    backup_file="/etc/ssh/sshd_config.bak.$(date +%Y%m%d_%H%M%S)"
    run_root cp /etc/ssh/sshd_config "$backup_file"
    run_root cp "$tmp_file" /etc/ssh/sshd_config
    rm -f "$tmp_file"
    trap - EXIT HUP INT TERM

    run_root sshd -t

    if command_exists systemctl; then
        if systemctl is-active --quiet sshd; then
            run_root systemctl restart sshd
        elif systemctl is-active --quiet ssh; then
            run_root systemctl restart ssh
        fi
    fi
}

main() {
    checkEnv

    banner_file=$(mktemp)
    trap 'rm -f "$banner_file"' EXIT HUP INT TERM

    cat > "$banner_file" <<'EOF'
*******************************************************************************
NOTICE: This system is for authorized use only. Unauthorized access or use
is prohibited and may result in disciplinary action and/or civil and criminal
penalties. All activity on this system may be monitored and recorded.
*******************************************************************************
EOF

    write_if_changed "$banner_file" "$ISSUE_FILE"
    write_if_changed "$banner_file" "$ISSUE_NET_FILE"
    configure_ssh_banner

    rm -f "$banner_file"
    trap - EXIT HUP INT TERM

    printf "%b\n" "${GREEN}Login banner configuration complete.${RC}"
}

main
