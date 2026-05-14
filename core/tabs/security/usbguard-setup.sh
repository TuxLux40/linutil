#!/bin/sh -e

. ../common-script.sh

DRY_RUN=${DRY_RUN:-0}

if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
fi

POLICY_FILE="/etc/usbguard/rules.conf"

run_root() {
    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] $*${RC}"
        return 0
    fi

    "$ESCALATION_TOOL" "$@"
}

confirm_usbguard() {
    if [ ! -t 0 ]; then
        printf "%b\n" "${RED}USBGuard setup requires an interactive terminal so you can explicitly acknowledge the device-lockout risk.${RC}"
        return 1
    fi

    printf "%b\n" "${RED}USBGuard will block USB devices that are not currently connected.${RC}"
    printf "%b\n" "${YELLOW}Make sure your keyboard and mouse are plugged in now. New devices will need manual authorization.${RC}"
    printf "%b" "Proceed with USBGuard setup? (y/N): "
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

install_usbguard() {
    if command_exists usbguard; then
        printf "%b\n" "${GREEN}USBGuard is already installed${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing USBGuard...${RC}"

    case "$PACKAGER" in
        pacman)
            run_root "$PACKAGER" -S --needed --noconfirm usbguard
            ;;
        apt-get|nala)
            run_root "$PACKAGER" install -y usbguard
            ;;
        dnf)
            run_root "$PACKAGER" install -y usbguard
            ;;
        zypper)
            run_root "$PACKAGER" install -y usbguard
            ;;
        apk)
            run_root "$PACKAGER" add usbguard
            ;;
        xbps-install)
            run_root "$PACKAGER" -Sy usbguard
            ;;
        eopkg)
            run_root "$PACKAGER" install -y usbguard
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            exit 1
            ;;
    esac
}

generate_policy() {
    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' EXIT HUP INT TERM

    printf "%b\n" "${YELLOW}Generating USB allowlist from currently connected devices${RC}"

    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would run: usbguard generate-policy > $POLICY_FILE${RC}"
        rm -f "$tmp_file"
        trap - EXIT HUP INT TERM
        return 0
    fi

    usbguard generate-policy > "$tmp_file"
    run_root mkdir -p /etc/usbguard
    run_root cp "$tmp_file" "$POLICY_FILE"
    rm -f "$tmp_file"
    trap - EXIT HUP INT TERM
}

enable_usbguard() {
    if ! command_exists systemctl; then
        printf "%b\n" "${RED}systemctl is required to enable USBGuard${RC}"
        exit 1
    fi

    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would run: systemctl enable --now usbguard${RC}"
        return 0
    fi

    run_root systemctl enable --now usbguard
}

main() {
    checkEnv

    if ! confirm_usbguard; then
        printf "%b\n" "${YELLOW}Aborting USBGuard setup${RC}"
        exit 1
    fi

    install_usbguard
    generate_policy
    enable_usbguard

    printf "%b\n" "${GREEN}USBGuard setup complete.${RC}"
    printf "%b\n" "${CYAN}Authorize future devices with: sudo usbguard allow-device <id>${RC}"
}

main
