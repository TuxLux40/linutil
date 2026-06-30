#!/usr/bin/env bash
set -e

. ../../common-script.sh

checkSystemd() {
    if ! command_exists systemctl; then
        printf "%b\n" "${RED}systemd is not available on this system. Cannot configure systemd-oomd.${RC}"
        return 1
    fi
    return 0
}

checkPSI() {
    if [ -f /proc/pressure/memory ]; then
        printf "%b\n" "${GREEN}Pressure Stall Information (PSI) is available.${RC}"
        return 0
    fi
    printf "%b\n" "${YELLOW}PSI not detected. systemd-oomd requires kernel PSI support (Linux 4.20+).${RC}"
    printf "%b\n" "${YELLOW}Check your kernel config: CONFIG_PSI=y${RC}"
    return 1
}

checkCgroupV2() {
    if [ -f /sys/fs/cgroup/cgroup.controllers ]; then
        printf "%b\n" "${GREEN}cgroup v2 is active — systemd-oomd will work optimally.${RC}"
        return 0
    fi
    printf "%b\n" "${YELLOW}Warning: cgroup v1 detected. systemd-oomd requires cgroup v2 for full functionality.${RC}"
    printf "%b\n" "${YELLOW}To enable cgroup v2, add 'systemd.unified_cgroup_hierarchy=1' to your kernel cmdline.${RC}"
    return 1
}

checkOomdUnit() {
    if systemctl list-unit-files systemd-oomd.service 2>/dev/null | grep -q "systemd-oomd"; then
        return 0
    fi
    printf "%b\n" "${RED}systemd-oomd.service not found. Requires systemd 247 or newer.${RC}"
    printf "%b\n" "${YELLOW}Your systemd version: $(systemctl --version | head -1)${RC}"
    return 1
}

configureOomd() {
    printf "%b\n" ""
    printf "%b\n" "${CYAN}--- systemd-oomd Configuration ---${RC}"
    printf "%b\n" "${YELLOW}Upstream defaults : SwapUsedLimit=90%  MemPressure=60%  Duration=30s${RC}"
    printf "%b\n" "${CYAN}CachyOS-tuned     : SwapUsedLimit=80%  MemPressure=40%  Duration=20s${RC}"
    printf "%b\n" "${YELLOW}Lower values = more aggressive; oomd kills processes sooner to prevent freezes.${RC}"
    printf "%b\n" ""

    printf "%b" "${CYAN}Swap used trigger % (default 80): ${RC}"
    read -r swap_limit
    swap_limit=${swap_limit:-80}

    printf "%b" "${CYAN}Memory pressure trigger % (default 40): ${RC}"
    read -r mem_pressure
    mem_pressure=${mem_pressure:-40}

    printf "%b" "${CYAN}Pressure duration in seconds before killing (default 20): ${RC}"
    read -r pressure_dur
    pressure_dur=${pressure_dur:-20}

    "$ESCALATION_TOOL" mkdir -p /etc/systemd/oomd.conf.d
    "$ESCALATION_TOOL" tee /etc/systemd/oomd.conf.d/60-tuning.conf > /dev/null << EOF
[OOM]
SwapUsedLimit=${swap_limit}%
DefaultMemoryPressureLimit=${mem_pressure}%
DefaultMemoryPressureDurationSec=${pressure_dur}s
EOF
    printf "%b\n" "${GREEN}Wrote /etc/systemd/oomd.conf.d/60-tuning.conf${RC}"
}

configureSlices() {
    printf "%b\n" "${CYAN}Enabling oomd monitoring on user.slice...${RC}"

    "$ESCALATION_TOOL" mkdir -p /etc/systemd/system/user.slice.d
    "$ESCALATION_TOOL" tee /etc/systemd/system/user.slice.d/10-oomd.conf > /dev/null << 'SLICEEOF'
[Slice]
ManagedOOMSwap=kill
ManagedOOMMemoryPressure=kill
SLICEEOF
    printf "%b\n" "${GREEN}Wrote /etc/systemd/system/user.slice.d/10-oomd.conf${RC}"

    "$ESCALATION_TOOL" mkdir -p /etc/systemd/system/user@.service.d
    "$ESCALATION_TOOL" tee /etc/systemd/system/user@.service.d/10-oomd.conf > /dev/null << 'SVCEOF'
[Service]
ManagedOOMMemoryPressure=kill
SVCEOF
    printf "%b\n" "${GREEN}Wrote /etc/systemd/system/user@.service.d/10-oomd.conf${RC}"
}

enableOomd() {
    "$ESCALATION_TOOL" systemctl daemon-reload
    "$ESCALATION_TOOL" systemctl enable --now systemd-oomd.service
    printf "%b\n" "${GREEN}systemd-oomd enabled and started.${RC}"
    OOMD_STATE=$(systemctl is-active systemd-oomd.service 2>/dev/null || echo 'unknown')
    printf "%b\n" "${CYAN}Status: ${OOMD_STATE}${RC}"
}

installEarlyoom() {
    if command_exists earlyoom; then
        printf "%b\n" "${GREEN}earlyoom is already installed.${RC}"
        return 0
    fi
    printf "%b\n" "${YELLOW}Installing earlyoom...${RC}"
    case "$PACKAGER" in
        pacman)
            "$AUR_HELPER" -S --needed --noconfirm earlyoom
            ;;
        apt-get | nala)
            "$ESCALATION_TOOL" "$PACKAGER" install -y earlyoom
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" install -y earlyoom
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y earlyoom
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add earlyoom
            ;;
        *)
            printf "%b\n" "${RED}Package manager '${PACKAGER}' is not supported for earlyoom installation.${RC}"
            return 1
            ;;
    esac
}

configureEarlyoom() {
    printf "%b\n" ""
    printf "%b\n" "${CYAN}--- earlyoom Configuration ---${RC}"
    printf "%b\n" "${YELLOW}earlyoom polls free memory and kills the most memory-hungry process when thresholds are crossed.${RC}"
    printf "%b\n" ""

    printf "%b" "${CYAN}Free memory % threshold to trigger kills (default 5): ${RC}"
    read -r mem_min
    mem_min=${mem_min:-5}

    printf "%b" "${CYAN}Free swap % threshold to trigger kills (default 5): ${RC}"
    read -r swap_min
    swap_min=${swap_min:-5}

    if [ -f /etc/default/earlyoom ]; then
        "$ESCALATION_TOOL" tee /etc/default/earlyoom > /dev/null << EOF
# earlyoom configuration — managed by linutil
EARLYOOM_ARGS="-m ${mem_min} -s ${swap_min} -r 0 --avoid '^(init|systemd|sshd|login|su|sudo)\$'"
EOF
        printf "%b\n" "${GREEN}earlyoom config written to /etc/default/earlyoom${RC}"
    else
        printf "%b\n" "${YELLOW}No /etc/default/earlyoom config file found; using package defaults (thresholds: -m ${mem_min} -s ${swap_min}).${RC}"
    fi

    "$ESCALATION_TOOL" systemctl enable --now earlyoom.service
    EARLYOOM_STATE=$(systemctl is-active earlyoom.service 2>/dev/null || echo 'unknown')
    printf "%b\n" "${GREEN}earlyoom enabled and started (status: ${EARLYOOM_STATE}).${RC}"
}

setupEarlyoom() {
    installEarlyoom && configureEarlyoom
}

main() {
    checkEnv
    checkEscalationTool

    printf "%b\n" "${CYAN}=== OOM Killer Tuning (CachyOS-inspired) ===${RC}"
    printf "%b\n" "${CYAN}Configures systemd-oomd to proactively kill memory-hungry processes${RC}"
    printf "%b\n" "${CYAN}before the system becomes unresponsive under memory pressure.${RC}"
    printf "%b\n" ""

    OOMD_AVAILABLE=false
    if checkSystemd; then
        checkPSI || true
        checkCgroupV2 || true
        if checkOomdUnit; then
            OOMD_AVAILABLE=true
        fi
    fi
    printf "%b\n" ""

    if [ "$OOMD_AVAILABLE" = "true" ]; then
        configureOomd
        configureSlices
        enableOomd
        printf "%b\n" ""
        printf "%b" "${CYAN}Also install earlyoom for additional userspace OOM protection? [y/N]: ${RC}"
        read -r do_earlyoom
        do_earlyoom=${do_earlyoom:-N}
        case "$do_earlyoom" in
            [yY]) setupEarlyoom ;;
            *) ;;
        esac
    else
        printf "%b\n" "${YELLOW}systemd-oomd is not available. Falling back to earlyoom.${RC}"
        printf "%b" "${CYAN}Install earlyoom as the OOM killer? [Y/n]: ${RC}"
        read -r do_earlyoom
        do_earlyoom=${do_earlyoom:-Y}
        case "$do_earlyoom" in
            [nN]) printf "%b\n" "${YELLOW}No OOM killer configured. Skipping.${RC}"; exit 0 ;;
            *) setupEarlyoom ;;
        esac
    fi

    printf "%b\n" ""
    printf "%b\n" "${GREEN}=== OOM Killer Tuning Complete! ===${RC}"
    if [ "$OOMD_AVAILABLE" = "true" ]; then
        printf "%b\n" "${CYAN}systemd-oomd will kill memory-hungry processes before your system freezes.${RC}"
        printf "%b\n" "${YELLOW}Check status : systemctl status systemd-oomd${RC}"
        printf "%b\n" "${YELLOW}View config  : cat /etc/systemd/oomd.conf.d/60-tuning.conf${RC}"
        printf "%b\n" "${YELLOW}View logs    : journalctl -u systemd-oomd -f${RC}"
    fi
}

main
