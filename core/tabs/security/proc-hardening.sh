#!/bin/sh -e

. ../common-script.sh

DRY_RUN=${DRY_RUN:-0}
PROC_HARDENING_HIDEPID=${PROC_HARDENING_HIDEPID:-ask}
TARGET_USER=${SUDO_USER:-$USER}

if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
fi

LIMITS_FILE="/etc/security/limits.d/90-hardening.conf"
COREDUMP_FILE="/etc/systemd/coredump.conf.d/hardening.conf"
PROC_MOUNT_FILE="/etc/systemd/system/proc.mount.d/hardening.conf"

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
        printf "%b\n" "${GREEN}$destination_file already matches the hardened baseline${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Writing $destination_file${RC}"

    if [ "$DRY_RUN" = "1" ]; then
        cat "$source_file"
        return 0
    fi

    run_root mkdir -p "$(dirname "$destination_file")"
    run_root cp "$source_file" "$destination_file"
}

confirm_hidepid() {
    case "$PROC_HARDENING_HIDEPID" in
        1|true|yes)
            return 0
            ;;
        0|false|no)
            return 1
            ;;
    esac

    if [ ! -t 0 ]; then
        printf "%b\n" "${YELLOW}Skipping hidepid=2 because no interactive terminal is available${RC}"
        return 1
    fi

    printf "%b\n" "${YELLOW}hidepid=2 hides other users' processes. Some monitoring tools may need access to the 'proc' group.${RC}"
    printf "%b" "Apply hidepid=2 and add ${TARGET_USER} to the proc group? (y/N): "
    read -r response

    case "$response" in
        [Yy]*)
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

apply_coredump_limits() {
    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' EXIT HUP INT TERM

    cat > "$tmp_file" <<'EOF'
# Managed by linutil proc-hardening.sh
* hard core 0
* soft core 0
EOF

    write_if_changed "$tmp_file" "$LIMITS_FILE"
    rm -f "$tmp_file"
    trap - EXIT HUP INT TERM
}

apply_systemd_coredump() {
    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' EXIT HUP INT TERM

    cat > "$tmp_file" <<'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF

    write_if_changed "$tmp_file" "$COREDUMP_FILE"
    rm -f "$tmp_file"
    trap - EXIT HUP INT TERM

    if command_exists systemctl; then
        if [ "$DRY_RUN" = "1" ]; then
            printf "%b\n" "${CYAN}[DRY RUN] Would run: systemctl daemon-reload${RC}"
        else
            run_root systemctl daemon-reload
        fi
    fi
}

apply_hidepid() {
    if ! command_exists systemctl; then
        printf "%b\n" "${YELLOW}Skipping hidepid=2 because systemd is not available${RC}"
        return 0
    fi

    if ! confirm_hidepid; then
        printf "%b\n" "${YELLOW}Skipping hidepid=2 hardening${RC}"
        return 0
    fi

    if ! getent group proc >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Creating proc group${RC}"
        run_root groupadd proc
    fi

    if ! id -nG "$TARGET_USER" | grep -qw proc; then
        printf "%b\n" "${YELLOW}Adding ${TARGET_USER} to the proc group${RC}"
        run_root usermod -a -G proc "$TARGET_USER"
    else
        printf "%b\n" "${GREEN}${TARGET_USER} is already in the proc group${RC}"
    fi

    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' EXIT HUP INT TERM

    cat > "$tmp_file" <<'EOF'
[Mount]
Options=nosuid,nodev,noexec,relatime,hidepid=2,gid=proc
EOF

    write_if_changed "$tmp_file" "$PROC_MOUNT_FILE"
    rm -f "$tmp_file"
    trap - EXIT HUP INT TERM

    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would run: systemctl daemon-reload${RC}"
        printf "%b\n" "${CYAN}[DRY RUN] Would remount /proc with hidepid=2${RC}"
        return 0
    fi

    proc_gid=$(getent group proc | awk -F: '{print $3}')
    run_root systemctl daemon-reload
    run_root mount -o remount,nosuid,nodev,noexec,relatime,hidepid=2,gid="$proc_gid" /proc
}

main() {
    checkEnv

    printf "%b\n" "${CYAN}Applying process hardening defaults...${RC}"
    apply_coredump_limits
    apply_systemd_coredump
    apply_hidepid

    printf "%b\n" "${GREEN}Process hardening complete.${RC}"
}

main
