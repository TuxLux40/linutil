#!/usr/bin/env bash -e

. ../../common-script.sh

# Detects hardware, installs VA-API drivers, configures browser hardware
# acceleration flags, sets up preload, and (Arch/KDE only) installs cgroup-based
# foreground boosters — all to reduce desktop app launch latency on laptops.

IS_LAPTOP=false
CPU_VENDOR=""
HAS_INTEL_GPU=false
HAS_NVIDIA_GPU=false
HAS_AMD_GPU=false
INTEL_LEGACY_GPU=false  # Haswell and older, needs libva-intel-driver
ON_WAYLAND=false

# ── Hardware detection ──────────────────────────────────────────────────────

detectHardware() {
    printf "%b\n" "${CYAN}Detecting hardware...${RC}"

    if ls /sys/class/power_supply/BAT* >/dev/null 2>&1; then
        IS_LAPTOP=true
        printf "%b\n" "${CYAN}System type: Laptop${RC}"
    else
        printf "%b\n" "${YELLOW}No battery detected. This script targets laptops.${RC}"
        printf "%b" "${YELLOW}Continue anyway? [y/N]: ${RC}"
        read -r proceed
        case "$proceed" in
            y|Y) ;;
            *) exit 0 ;;
        esac
    fi

    grep -q "GenuineIntel" /proc/cpuinfo && CPU_VENDOR="intel"
    grep -q "AuthenticAMD" /proc/cpuinfo && CPU_VENDOR="amd"
    CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
    printf "%b\n" "${CYAN}CPU: ${CPU_MODEL}${RC}"

    # Intel GPU: distinguish iHD-capable (Broadwell+) vs legacy i965 (Haswell-)
    if lspci 2>/dev/null | grep -iE "VGA|3D|Display" | grep -qi "Intel"; then
        HAS_INTEL_GPU=true
        if lspci 2>/dev/null | grep -iE "VGA|3D|Display" | grep -i "Intel" | grep -qiE "Sandy Bridge|Ivy Bridge|Haswell|Bay Trail|Celeron.*[0-9]{4}[A-Z]?.*[Gg][Tt]"; then
            INTEL_LEGACY_GPU=true
        fi
    fi

    lspci 2>/dev/null | grep -iE "VGA|3D|Display" | grep -qi "NVIDIA" && HAS_NVIDIA_GPU=true
    lspci 2>/dev/null | grep -iE "VGA|3D|Display" | grep -qiE "AMD|Radeon"  && HAS_AMD_GPU=true

    printf "%b\n" "${CYAN}GPUs found: Intel=${HAS_INTEL_GPU} NVIDIA=${HAS_NVIDIA_GPU} AMD=${HAS_AMD_GPU}${RC}"

    # Wayland detection — check env and fallback socket path
    if [ "${XDG_SESSION_TYPE:-}" = "wayland" ] || [ -n "${WAYLAND_DISPLAY:-}" ]; then
        ON_WAYLAND=true
        printf "%b\n" "${CYAN}Session: Wayland${RC}"
    else
        printf "%b\n" "${CYAN}Session: X11 (browser Wayland flags will be skipped)${RC}"
    fi
}

# ── VA-API hardware video decode ────────────────────────────────────────────

installVaapi() {
    printf "%b\n" "${YELLOW}Installing VA-API hardware video acceleration...${RC}"

    case "$PACKAGER" in
        pacman)
            if [ "$HAS_INTEL_GPU" = "true" ]; then
                if [ "$INTEL_LEGACY_GPU" = "true" ]; then
                    "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm libva-intel-driver libva-utils
                else
                    "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm intel-media-driver libva-utils
                fi
            fi
            if [ "$HAS_AMD_GPU" = "true" ]; then
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm libva-mesa-driver libva-utils
            fi
            ;;
        apt-get|nala)
            if [ "$HAS_INTEL_GPU" = "true" ]; then
                "$ESCALATION_TOOL" "$PACKAGER" install -y vainfo intel-media-va-driver-non-free 2>/dev/null \
                    || "$ESCALATION_TOOL" "$PACKAGER" install -y vainfo intel-media-va-driver \
                    || "$ESCALATION_TOOL" "$PACKAGER" install -y vainfo i965-va-driver
            fi
            if [ "$HAS_AMD_GPU" = "true" ]; then
                "$ESCALATION_TOOL" "$PACKAGER" install -y vainfo mesa-va-drivers
            fi
            ;;
        dnf)
            if [ "$HAS_INTEL_GPU" = "true" ]; then
                "$ESCALATION_TOOL" "$PACKAGER" install -y intel-media-driver libva-utils
            fi
            if [ "$HAS_AMD_GPU" = "true" ]; then
                "$ESCALATION_TOOL" "$PACKAGER" install -y mesa-va-drivers libva-utils
            fi
            ;;
        *)
            printf "%b\n" "${YELLOW}Package manager not supported for automated VA-API setup, skipping.${RC}"
            ;;
    esac
}

verifyVaapi() {
    if ! command_exists vainfo; then
        return
    fi
    printf "%b\n" "${CYAN}Verifying VA-API...${RC}"
    if vainfo 2>/dev/null | grep -q "VAProfile"; then
        DRIVER_VER=$(vainfo 2>/dev/null | grep "Driver version" | head -1 | sed 's/.*: //')
        printf "%b\n" "${GREEN}VA-API OK — ${DRIVER_VER}${RC}"
    else
        printf "%b\n" "${YELLOW}VA-API reported no profiles. Driver may not support this GPU.${RC}"
        printf "%b\n" "${YELLOW}Run 'vainfo' manually after reboot to confirm.${RC}"
    fi
}

# ── Browser hardware acceleration flags ─────────────────────────────────────

configureBrowserFlags() {
    if [ "$ON_WAYLAND" = "false" ]; then
        printf "%b\n" "${YELLOW}Skipping browser Wayland/VA-API flags (X11 session).${RC}"
        return
    fi

    FLAGS="--ozone-platform=wayland
--enable-features=VaapiVideoDecodeLinuxGL,VaapiVideoEncoder,WaylandWindowDecorations"

    WRITTEN=0
    # Map: binary name → flags config file
    for entry in "brave:brave-flags.conf" "chromium:chromium-flags.conf" \
                 "google-chrome-stable:google-chrome-flags.conf" \
                 "microsoft-edge:microsoft-edge-flags.conf"; do
        browser="${entry%%:*}"
        conf_name="${entry##*:}"
        conf_file="$HOME/.config/${conf_name}"

        if ! command_exists "$browser"; then
            continue
        fi

        if [ -f "$conf_file" ] && grep -q "VaapiVideoDecodeLinuxGL" "$conf_file" 2>/dev/null; then
            printf "%b\n" "${GREEN}${conf_name} already configured, skipping.${RC}"
            WRITTEN=$((WRITTEN + 1))
            continue
        fi

        printf "%b\n" "$FLAGS" > "$conf_file"
        printf "%b\n" "${GREEN}Wrote ${conf_file}${RC}"
        WRITTEN=$((WRITTEN + 1))
    done

    if [ "$WRITTEN" -eq 0 ]; then
        printf "%b\n" "${YELLOW}No supported Chromium-based browser found in PATH, skipping flags.${RC}"
    else
        printf "%b\n" "${YELLOW}Restart any open browsers for the flags to take effect.${RC}"
    fi
}

# ── Preload (adaptive disk readahead daemon) ─────────────────────────────────

installPreload() {
    if command_exists preload; then
        printf "%b\n" "${GREEN}preload already installed.${RC}"
    else
        printf "%b\n" "${YELLOW}Installing preload...${RC}"
        case "$PACKAGER" in
            pacman)
                "$AUR_HELPER" -S --needed --noconfirm preload
                ;;
            apt-get|nala|dnf)
                "$ESCALATION_TOOL" "$PACKAGER" install -y preload
                ;;
            *)
                printf "%b\n" "${YELLOW}Cannot install preload for this package manager, skipping.${RC}"
                return
                ;;
        esac
    fi

    "$ESCALATION_TOOL" systemctl enable --now preload
    printf "%b\n" "${GREEN}preload enabled and running.${RC}"
    printf "%b\n" "${YELLOW}It learns your usage patterns over a few days — cold starts will improve over time.${RC}"
}

# ── KDE foreground/cgroup boosters (Arch / pacman only) ─────────────────────

installKdeBoosters() {
    [ "$PACKAGER" = "pacman" ] || return 0

    if ! command_exists plasmashell && ! pgrep -x plasmashell >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}KDE Plasma not detected, skipping KDE foreground boosters.${RC}"
        return
    fi

    printf "%b\n" "${YELLOW}Installing KDE foreground/cgroup boosters...${RC}"
    "$AUR_HELPER" -S --needed --noconfirm plasma-foreground-booster dmemcg-booster

    "$ESCALATION_TOOL" systemctl enable --now dmemcg-booster-system 2>/dev/null \
        || printf "%b\n" "${YELLOW}dmemcg-booster-system already running or unavailable.${RC}"

    systemctl --user enable --now dmemcg-booster-user 2>/dev/null \
        || printf "%b\n" "${YELLOW}dmemcg-booster-user already running or unavailable.${RC}"

    printf "%b\n" "${GREEN}KDE cgroup boosters active — foreground apps now get CPU scheduling priority.${RC}"
}

# ── Main ─────────────────────────────────────────────────────────────────────

main() {
    checkEnv
    checkEscalationTool

    detectHardware

    printf "%b\n" ""
    printf "%b\n" "${CYAN}=== VA-API Hardware Video Acceleration ===${RC}"
    installVaapi
    verifyVaapi

    printf "%b\n" ""
    printf "%b\n" "${CYAN}=== Browser Hardware Acceleration Flags ===${RC}"
    configureBrowserFlags

    printf "%b\n" ""
    printf "%b\n" "${CYAN}=== Preload (Adaptive Readahead) ===${RC}"
    installPreload

    printf "%b\n" ""
    printf "%b\n" "${CYAN}=== KDE Foreground Boosters ===${RC}"
    installKdeBoosters

    printf "%b\n" ""
    printf "%b\n" "${GREEN}=== Laptop tuning complete! ===${RC}"
    printf "%b\n" "${YELLOW}Reboot or log out and back in for all changes to fully take effect.${RC}"
    printf "%b\n" "${YELLOW}preload improves over the next few days as it learns which apps you use.${RC}"
}

main
