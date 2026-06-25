#!/bin/sh -e

. ../../common-script.sh

LIMINE_DEFAULT="/etc/default/limine"
PARAM="nvme_core.default_ps_max_latency_us=0"

checkAlreadyApplied() {
    if grep -q "$PARAM" "$LIMINE_DEFAULT" 2>/dev/null; then
        printf "%b\n" "${GREEN}NVMe APST is already disabled (${PARAM} present in ${LIMINE_DEFAULT}).${RC}"
        exit 0
    fi
}

backupConfig() {
    BACKUP="${LIMINE_DEFAULT}.backup.$(date +%Y%m%d_%H%M%S)"
    printf "%b\n" "${YELLOW}Backing up ${LIMINE_DEFAULT} to ${BACKUP}...${RC}"
    "$ESCALATION_TOOL" cp "$LIMINE_DEFAULT" "$BACKUP"
}

applyFix() {
    printf "%b\n" "${YELLOW}Removing 'splash' and injecting ${PARAM} into kernel cmdline...${RC}"

    "$ESCALATION_TOOL" sed -i \
        "s/quiet nowatchdog splash rw/quiet nowatchdog ${PARAM} rw/" \
        "$LIMINE_DEFAULT"

    if ! grep -q "$PARAM" "$LIMINE_DEFAULT"; then
        printf "%b\n" "${RED}Pattern 'quiet nowatchdog splash rw' not found in ${LIMINE_DEFAULT}.${RC}"
        printf "%b\n" "${RED}Add '${PARAM}' manually to a KERNEL_CMDLINE line in ${LIMINE_DEFAULT}.${RC}"
        exit 1
    fi

    printf "%b\n" "${GREEN}Kernel cmdline updated.${RC}"
}

patchLimineConf() {
    LIMINE_CONF="/boot/limine.conf"
    if [ ! -f "$LIMINE_CONF" ]; then
        return 0
    fi
    if grep -q "$PARAM" "$LIMINE_CONF" 2>/dev/null; then
        printf "%b\n" "${GREEN}${LIMINE_CONF} already contains ${PARAM}.${RC}"
        return 0
    fi
    printf "%b\n" "${YELLOW}Patching ${LIMINE_CONF} directly (takes effect without kernel reinstall)...${RC}"
    BOOT_BACKUP="${LIMINE_CONF}.backup.$(date +%Y%m%d_%H%M%S)"
    "$ESCALATION_TOOL" cp "$LIMINE_CONF" "$BOOT_BACKUP"
    "$ESCALATION_TOOL" sed -i "s/splash rw/${PARAM} rw/g" "$LIMINE_CONF"
    printf "%b\n" "${GREEN}${LIMINE_CONF} patched.${RC}"
}

regenerateBootEntries() {
    if ! command_exists limine-entry-tool; then
        printf "%b\n" "${YELLOW}limine-entry-tool not found.${RC}"
        printf "%b\n" "${YELLOW}If using GRUB: run 'sudo grub-mkconfig -o /boot/grub/grub.cfg'${RC}"
        printf "%b\n" "${YELLOW}If using systemd-boot: update your loader entry cmdline manually.${RC}"
    fi
    # limine-entry-tool has no standalone regenerate command; /etc/default/limine
    # is picked up automatically on the next kernel install via pacman hooks.
    # Patch /boot/limine.conf directly so the change takes effect on next reboot.
    patchLimineConf
}

checkEnv
checkEscalationTool
checkAlreadyApplied
backupConfig
applyFix
regenerateBootEntries

printf "%b\n" ""
printf "%b\n" "${GREEN}Done. Reboot to activate the fix.${RC}"
printf "%b\n" "${CYAN}After reboot, verify with: cat /sys/module/nvme_core/parameters/default_ps_max_latency_us${RC}"
printf "%b\n" "${CYAN}Expected output: 0${RC}"
