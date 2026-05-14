#!/bin/sh -e

. ../common-script.sh

DRY_RUN=${DRY_RUN:-0}

if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
fi

SYSCTL_FILE="/etc/sysctl.d/90-hardening.conf"
MODULE_FILE="/etc/modprobe.d/blacklist-uncommon-net.conf"

run_root() {
    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] $*${RC}"
        return 0
    fi

    "$ESCALATION_TOOL" "$@"
}

service_active() {
    command_exists systemctl && systemctl is-active --quiet "$1"
}

has_bluetooth() {
    [ -d /sys/class/bluetooth ] && ls /sys/class/bluetooth/* >/dev/null 2>&1
}

docker_or_virt() {
    command_exists docker || command_exists podman || service_active docker || service_active podman || service_active libvirtd
}

sysctl_key_available() {
    [ -e "/proc/sys/$(printf '%s' "$1" | tr '.' '/')" ]
}

append_sysctl_if_available() {
    target_file=$1
    key=$2
    value=$3

    if sysctl_key_available "$key"; then
        printf '%s = %s\n' "$key" "$value" >> "$target_file"
    fi
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

build_sysctl_file() {
    tmp_file=$1

    cat > "$tmp_file" <<'EOF'
# Managed by linutil kernel-hardening.sh
EOF

    append_sysctl_if_available "$tmp_file" "net.core.bpf_jit_harden" "2"
    append_sysctl_if_available "$tmp_file" "fs.protected_fifos" "2"
    append_sysctl_if_available "$tmp_file" "fs.protected_regular" "2"
    append_sysctl_if_available "$tmp_file" "fs.suid_dumpable" "0"
    append_sysctl_if_available "$tmp_file" "net.ipv4.conf.all.log_martians" "1"
    append_sysctl_if_available "$tmp_file" "net.ipv4.conf.default.log_martians" "1"

    if ! docker_or_virt; then
        append_sysctl_if_available "$tmp_file" "net.ipv4.conf.all.send_redirects" "0"
        append_sysctl_if_available "$tmp_file" "net.ipv4.conf.default.send_redirects" "0"
    else
        printf "%b\n" "${YELLOW}Skipping send_redirects hardening because container or virtualization tooling was detected${RC}"
    fi

    if ! docker_or_virt && ! service_active tailscaled; then
        append_sysctl_if_available "$tmp_file" "net.ipv4.conf.all.forwarding" "0"
        append_sysctl_if_available "$tmp_file" "net.ipv4.conf.default.forwarding" "0"
    else
        printf "%b\n" "${YELLOW}Skipping forwarding hardening because container tooling or Tailscale was detected${RC}"
    fi

    if ! has_bluetooth; then
        append_sysctl_if_available "$tmp_file" "dev.tty.ldisc_autoload" "0"
    else
        printf "%b\n" "${YELLOW}Skipping tty line discipline hardening because Bluetooth hardware was detected${RC}"
    fi

    append_sysctl_if_available "$tmp_file" "kernel.unprivileged_bpf_disabled" "1"
}

build_module_blacklist() {
    tmp_file=$1

    cat > "$tmp_file" <<'EOF'
# Managed by linutil kernel-hardening.sh
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false
EOF
}

apply_sysctl() {
    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would run: sysctl --load $SYSCTL_FILE${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Loading hardened sysctl settings${RC}"
    run_root sysctl --load "$SYSCTL_FILE"
}

main() {
    checkEnv

    sysctl_tmp=$(mktemp)
    module_tmp=$(mktemp)
    trap 'rm -f "$sysctl_tmp" "$module_tmp"' EXIT HUP INT TERM

    printf "%b\n" "${CYAN}Applying kernel hardening defaults...${RC}"
    build_sysctl_file "$sysctl_tmp"
    build_module_blacklist "$module_tmp"

    write_if_changed "$sysctl_tmp" "$SYSCTL_FILE"
    write_if_changed "$module_tmp" "$MODULE_FILE"
    apply_sysctl

    printf "%b\n" "${GREEN}Kernel hardening complete.${RC}"
}

main
