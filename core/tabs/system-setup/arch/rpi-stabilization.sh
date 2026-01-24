#!/bin/sh
set -e

# Raspberry Pi 4 (Arch Linux ARM) Stabilization: ZRAM, EarlyOOM, OOM protection for sshd/tailscaled, and journald limits/rotation

info() { printf "[INFO] %s\n" "$*"; }
warn() { printf "[WARN] %s\n" "$*"; }
err() { printf "[ERROR] %s\n" "$*" >&2; }

is_raspberry_pi() {
    if [ -r /sys/firmware/devicetree/base/model ]; then
        if grep -qi "raspberry pi" /sys/firmware/devicetree/base/model; then
            return 0
        fi
    fi
    if [ -r /proc/device-tree/model ]; then
        if grep -qi "raspberry pi" /proc/device-tree/model; then
            return 0
        fi
    fi
    if grep -qi "raspberry pi" /proc/cpuinfo 2>/dev/null; then
        return 0
    fi
    return 1
}

require_escalation() {
    if [ "$(id -u)" != "0" ]; then
        if command -v sudo >/dev/null 2>&1; then
            SUDO="sudo"
        elif command -v doas >/dev/null 2>&1; then
            SUDO="doas"
        else
            err "This script requires root or sudo/doas."
            exit 1
        fi
    else
        SUDO=""
    fi
}

require_commands() {
    for c in pacman systemctl tee; do
        if ! command -v "$c" >/dev/null 2>&1; then
            err "Missing required command: $c"
            exit 1
        fi
    done
}

write_file() {
    # usage: write_file <path> << 'EOF' ... EOF
    dest="$1"
    dir="$(dirname "$dest")"
    [ -d "$dir" ] || ${SUDO} mkdir -p "$dir"
    # shellcheck disable=SC2094
    ${SUDO} tee "$dest" >/dev/null
}

start_unit_if_exists() {
    unit="$1"
    if systemctl list-unit-files | grep -q "^$unit"; then
        ${SUDO} systemctl start "$unit" || true
    else
        warn "Unit $unit not found; skipping start"
    fi
}

restart_if_active() {
    unit="$1"
    if systemctl is-active --quiet "$unit"; then
        ${SUDO} systemctl restart "$unit" || true
    fi
}

main() {
    if ! is_raspberry_pi; then
        err "This script is intended for Raspberry Pi devices."
        exit 1
    fi
    require_escalation
    require_commands

    info "Installing and configuring ZRAM swap (zram-generator)"
    ${SUDO} pacman -S --needed --noconfirm zram-generator
    cat << 'EOF' | write_file /etc/systemd/zram-generator.conf
[zram0]
zram-size = ram / 3
compression-algorithm = lz4
swap-priority = 100
EOF
    ${SUDO} systemctl daemon-reload
    # Try both possible units; one will exist depending on generator version
    ${SUDO} systemctl start systemd-zram-setup@zram0.service || ${SUDO} systemctl start dev-zram0.swap || true

    info "Creating additional SSD-backed swapfile (generous size)"
    # Create a large swapfile to complement zram; default 8G, override via SWAPFILE_SIZE env (e.g., 16G)
    SWAPFILE_SIZE="${SWAPFILE_SIZE:-16G}"
    if ! grep -q '^/swapfile' /etc/fstab; then
        # Detect FS type for / and adjust for btrfs (disable CoW)
        FSTYPE="$(findmnt -no FSTYPE / || echo unknown)"
        if [ "$FSTYPE" = "btrfs" ]; then
            ${SUDO} touch /swapfile
            ${SUDO} chattr +C /swapfile || true
        fi
        if command -v fallocate >/dev/null 2>&1; then
            ${SUDO} fallocate -l "$SWAPFILE_SIZE" /swapfile
        else
            # Fallback to dd (convert G to MiB)
            case "$SWAPFILE_SIZE" in
                *G|*g) SZ_MB=$(( ${SWAPFILE_SIZE%[Gg]} * 1024 )) ;;
                *M|*m) SZ_MB=${SWAPFILE_SIZE%[Mm]} ;;
                *) SZ_MB=8192 ;;
            esac
            ${SUDO} dd if=/dev/zero of=/swapfile bs=1M count="$SZ_MB" status=progress
        fi
        ${SUDO} chmod 600 /swapfile
        ${SUDO} mkswap /swapfile
        ${SUDO} sh -c 'echo "/swapfile none swap defaults,pri=50 0 0" >> /etc/fstab'
    fi
    ${SUDO} swapon /swapfile || true

    info "Installing and enabling earlyoom"
    ${SUDO} pacman -S --needed --noconfirm earlyoom
    cat << 'EOF' | write_file /etc/default/earlyoom
EARLYOOM_ARGS="-m 10 -s 10 -r 60 --avoid (^sshd$|^tailscaled$)"
EOF
    ${SUDO} systemctl enable --now earlyoom.service
    ${SUDO} systemctl disable --now systemd-oomd.service || true

    info "Applying OOM protection for sshd and tailscaled"
    cat << 'EOF' | write_file /etc/systemd/system/sshd.service.d/10-oom-protect.conf
[Service]
OOMScoreAdjust=-900
EOF
    cat << 'EOF' | write_file /etc/systemd/system/tailscaled.service.d/10-oom-protect.conf
[Service]
OOMScoreAdjust=-900
EOF
    ${SUDO} systemctl daemon-reload
    restart_if_active sshd
    restart_if_active tailscaled

    info "Configuring journald limits and auto rotation/vacuum"
    cat << 'EOF' | write_file /etc/systemd/journald.conf.d/limits.conf
[Journal]
SystemMaxUse=2G
SystemMaxFileSize=200M
MaxRetentionSec=14day
RateLimitIntervalSec=30s
RateLimitBurst=1000
EOF
    ${SUDO} systemctl restart systemd-journald
    ${SUDO} journalctl --rotate || true
    ${SUDO} journalctl --vacuum-size=2G --vacuum-time=14d || true

    info "Verification summary"
    swapon --show || true
    systemctl is-active earlyoom && systemctl is-enabled earlyoom || true
    systemctl show sshd -p OOMScoreAdjust || true
    systemctl show tailscaled -p OOMScoreAdjust || true
    journalctl --disk-usage || true

    info "Done. SSH/Tailscale protected, ZRAM+earlyoom configured, journald limited."
}

main "$@"
