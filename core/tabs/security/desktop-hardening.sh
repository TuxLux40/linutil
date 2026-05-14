#!/bin/sh -e

. ../common-script.sh

DRY_RUN=${DRY_RUN:-0}
SCRIPT_DIR=$(CDPATH= cd -- "$(dirname "$0")" && pwd)

if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
fi

APPLIED_FILE=$(mktemp)
SKIPPED_FILE=$(mktemp)
RECOMMENDED_FILE=$(mktemp)

cleanup() {
    rm -f "$APPLIED_FILE" "$SKIPPED_FILE" "$RECOMMENDED_FILE"
}

trap cleanup EXIT HUP INT TERM

record_item() {
    file=$1
    item=$2
    printf -- '- %s\n' "$item" >> "$file"
}

run_sibling_script() {
    label=$1
    script_name=$2
    shift 2

    printf "%b\n" "${CYAN}${label}${RC}"

    if [ "$DRY_RUN" = "1" ]; then
        env DRY_RUN=1 "$@" sh "$SCRIPT_DIR/$script_name"
        return 0
    fi

    env "$@" sh "$SCRIPT_DIR/$script_name"
}

selinux_native() {
    command_exists getenforce && [ "$(getenforce 2>/dev/null)" != "Disabled" ]
}

select_firewall_script() {
    if command_exists firewall-cmd; then
        printf '%s\n' "firewalld-baselines.sh"
    else
        printf '%s\n' "ufw-baselines.sh"
    fi
}

show_summary() {
    printf "%b\n" "${GREEN}Desktop hardening complete.${RC}"

    printf "%b\n" "${CYAN}Applied baseline:${RC}"
    if [ -s "$APPLIED_FILE" ]; then
        cat "$APPLIED_FILE"
    else
        printf '%s\n' "- No baseline changes were applied"
    fi

    printf "%b\n" "${CYAN}Skipped or left opt-in:${RC}"
    if [ -s "$SKIPPED_FILE" ]; then
        cat "$SKIPPED_FILE"
    else
        printf '%s\n' "- Nothing was skipped"
    fi

    printf "%b\n" "${CYAN}Recommended next steps:${RC}"
    cat "$RECOMMENDED_FILE"
}

main() {
    checkEnv

    printf "%b\n" "${CYAN}Applying GrapheneOS-inspired desktop hardening defaults...${RC}"
    printf "%b\n" "${YELLOW}This profile favors passive controls and GUI-manageable tooling where practical.${RC}"

    if selinux_native; then
        printf "%b\n" "${YELLOW}Native SELinux was detected. Keeping the distro-native MAC stack instead of layering AppArmor on top.${RC}"
        record_item "$SKIPPED_FILE" "AppArmor setup skipped because native SELinux is active"
        record_item "$RECOMMENDED_FILE" "Use the distro-native SELinux tooling and GUI frontends where available instead of replacing it with AppArmor"
    else
        run_sibling_script "Applying AppArmor baseline..." "apparmor-setup.sh"
        record_item "$APPLIED_FILE" "AppArmor baseline with AppAnvil GUI support"
        record_item "$RECOMMENDED_FILE" "Reboot after AppArmor changes so the bootloader kernel-parameter update takes effect"
    fi

    run_sibling_script "Applying auditd baseline..." "auditd-setup.sh"
    record_item "$APPLIED_FILE" "auditd rules for auditing and incident visibility"

    run_sibling_script "Applying ClamAV baseline..." "clamav-setup.sh"
    record_item "$APPLIED_FILE" "ClamAV with the ClamUI graphical frontend"

    firewall_script=$(select_firewall_script)
    run_sibling_script "Applying desktop firewall defaults..." "$firewall_script" "HARDENING_PROFILE=desktop"
    record_item "$APPLIED_FILE" "Desktop-focused firewall baseline without automatically opening inbound services"

    run_sibling_script "Applying kernel hardening..." "kernel-hardening.sh"
    record_item "$APPLIED_FILE" "Kernel sysctl and uncommon-network-protocol hardening"

    run_sibling_script "Applying process hardening..." "proc-hardening.sh" "PROC_HARDENING_HIDEPID=0"
    record_item "$APPLIED_FILE" "Core-dump hardening"
    record_item "$SKIPPED_FILE" "hidepid=2 process isolation is available separately via Process Hardening but is not enabled automatically"

    run_sibling_script "Applying PAM hardening..." "pam-hardening.sh"
    record_item "$APPLIED_FILE" "Password policy hardening with pwquality"

    if command_exists sshd; then
        record_item "$SKIPPED_FILE" "SSH hardening was not applied automatically; run SSH Hardening if this desktop exposes an SSH server"
        record_item "$RECOMMENDED_FILE" "If sshd is enabled, run SSH Hardening and keep SSH behind the firewall or a VPN"
    fi

    record_item "$SKIPPED_FILE" "USBGuard is available separately but remains opt-in because it can lock out newly attached input devices"
    record_item "$SKIPPED_FILE" "YubiKey PAM remains opt-in because it can lock you out if misconfigured"
    record_item "$SKIPPED_FILE" "Login banners remain optional because they are more compliance-focused than desktop-focused"

    record_item "$RECOMMENDED_FILE" "Use AppAnvil for AppArmor profile tuning and ClamUI for malware scans"
    record_item "$RECOMMENDED_FILE" "Use Flatpak plus Flatseal to reduce application access to the filesystem and desktop portals"
    record_item "$RECOMMENDED_FILE" "Use Firejail for browsers, PDF readers, messaging apps, and other untrusted content handlers; prefer Firetools when your distro packages it"
    record_item "$RECOMMENDED_FILE" "Use Lynis for periodic hardening audits and AIDE for filesystem integrity monitoring"
    record_item "$RECOMMENDED_FILE" "Use Timeshift or Snapper with a GUI such as Btrfs Assistant for rollback and recovery"
    record_item "$RECOMMENDED_FILE" "Prefer full-disk encryption with LUKS for at-rest protection when the system is installed or reinstalled"
    record_item "$RECOMMENDED_FILE" "Keep USBGuard and YubiKey PAM as opt-in upgrades once the baseline is stable on your machine"
    record_item "$RECOMMENDED_FILE" "GrapheneOS-style verified boot, attestation, and Android app sandboxing cannot be fully replicated on a general-purpose Linux desktop"

    show_summary
}

main
