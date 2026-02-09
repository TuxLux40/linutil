#!/bin/sh -e

. ../common-script.sh

USER_NAME=${USER:-$(id -un)}
DESKTOP_DIR="$HOME/.local/share/applications"
AUTOSTART_DIR="$HOME/.config/autostart"
UDEV_RULE_NAME="60-openrgb.rules"
UDEV_RULE_URL="https://openrgb.org/releases/release_0.9/${UDEV_RULE_NAME}"
OPENRGB_INSTALL_SOURCE="repo"
AUTOSTART_ENTRY="openrgb.desktop"

print_header() {
    printf "%b\n" "${CYAN}$1${RC}"
}

install_openrgb_flatpak() {
    checkFlatpak
    flatpak install -y flathub org.openrgb.OpenRGB
    printf "%b\n" "${GREEN}Installed OpenRGB via Flatpak.${RC}"
}

install_openrgb() {
    print_header "Update system and install OpenRGB"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -Syu --noconfirm || printf "%b\n" "${YELLOW}Update skipped.${RC}"
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm openrgb qt5-tools i2c-tools
            if [ -n "$AUR_HELPER" ]; then
                "$AUR_HELPER" -S --needed --noconfirm openrgb-plugin-effects-git
            else
                printf "%b\n" "${YELLOW}AUR helper not available, skipping effects plugin.${RC}"
            fi
            if command_exists flatpak && flatpak list --app | grep -qi openrgb; then
                flatpak uninstall openrgb -y
                printf "%b\n" "${GREEN}Removed Flatpak OpenRGB.${RC}"
            fi
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            if ! "$ESCALATION_TOOL" "$PACKAGER" install -y openrgb i2c-tools; then
                printf "%b\n" "${YELLOW}Repo install failed. Falling back to Flatpak.${RC}"
                OPENRGB_INSTALL_SOURCE="flatpak"
                install_openrgb_flatpak
            fi
            ;;
        dnf)
            if ! "$ESCALATION_TOOL" "$PACKAGER" install -y openrgb i2c-tools; then
                printf "%b\n" "${YELLOW}Repo install failed. Falling back to Flatpak.${RC}"
                OPENRGB_INSTALL_SOURCE="flatpak"
                install_openrgb_flatpak
            fi
            ;;
        zypper)
            if ! "$ESCALATION_TOOL" "$PACKAGER" -n install openrgb i2c-tools; then
                printf "%b\n" "${YELLOW}Repo install failed. Falling back to Flatpak.${RC}"
                OPENRGB_INSTALL_SOURCE="flatpak"
                install_openrgb_flatpak
            fi
            ;;
        eopkg)
            if ! "$ESCALATION_TOOL" "$PACKAGER" install -y openrgb i2c-tools; then
                printf "%b\n" "${YELLOW}Repo install failed. Falling back to Flatpak.${RC}"
                OPENRGB_INSTALL_SOURCE="flatpak"
                install_openrgb_flatpak
            fi
            ;;
        apk|xbps-install)
            printf "%b\n" "${YELLOW}No OpenRGB package for ${PACKAGER}. Using Flatpak.${RC}"
            OPENRGB_INSTALL_SOURCE="flatpak"
            install_openrgb_flatpak
            ;;
        *)
            printf "%b\n" "${RED}OpenRGB install is not supported for ${PACKAGER}.${RC}"
            exit 1
            ;;
    esac
}

install_udev_rules() {
    print_header "Install OpenRGB udev rules"
    udev_tmp=$(mktemp)
    trap 'rm -f "$udev_tmp"' EXIT
    curl -fsSLo "$udev_tmp" "$UDEV_RULE_URL"
    if [ -f "/usr/lib/udev/rules.d/${UDEV_RULE_NAME}" ]; then
        if [ -f "/etc/udev/rules.d/${UDEV_RULE_NAME}" ]; then
            printf "%b\n" "${YELLOW}Duplicate udev rules detected in /etc and /usr/lib. Removing /etc copy.${RC}"
            "$ESCALATION_TOOL" rm -f "/etc/udev/rules.d/${UDEV_RULE_NAME}"
        fi
        printf "%b\n" "${GREEN}Using packaged udev rules from /usr/lib.${RC}"
        return 0
    fi

    if [ -f "/etc/udev/rules.d/${UDEV_RULE_NAME}" ] && cmp -s "$udev_tmp" "/etc/udev/rules.d/${UDEV_RULE_NAME}"; then
        printf "%b\n" "${GREEN}Udev rules already up to date.${RC}"
        return 0
    fi

    "$ESCALATION_TOOL" cp "$udev_tmp" "/etc/udev/rules.d/${UDEV_RULE_NAME}"
    "$ESCALATION_TOOL" udevadm control --reload-rules
    "$ESCALATION_TOOL" udevadm trigger
    printf "%b\n" "${GREEN}Udev rules loaded. Log out/in to apply group changes.${RC}"
}

load_i2c_modules() {
    print_header "Load i2c modules"
    "$ESCALATION_TOOL" modprobe i2c-dev i2c-piix4 i2c-smbus nct6775
    printf "%s\n" "i2c-dev i2c-piix4 i2c-smbus nct6775" | "$ESCALATION_TOOL" tee /etc/modules-load.d/openrgb.conf >/dev/null
    if lsmod | grep -q i2c; then
        printf "%b\n" "${GREEN}i2c modules are active.${RC}"
    fi
}

ensure_group() {
    group_name=$1
    if ! getent group "$group_name" >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Creating group: ${group_name}${RC}"
        "$ESCALATION_TOOL" groupadd "$group_name"
        printf "%b\n" "${GREEN}Group ${group_name} created.${RC}"
    else
        printf "%b\n" "${CYAN}Group ${group_name} already exists.${RC}"
    fi
}

add_user_to_group() {
    group_name=$1
    if ! getent group "$group_name" >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Group ${group_name} not found, skipping.${RC}"
        return 1
    fi
    
    if groups "$USER_NAME" | grep -q "\b${group_name}\b"; then
        printf "%b\n" "${CYAN}User ${USER_NAME} already in group ${group_name}.${RC}"
    else
        printf "%b\n" "${YELLOW}Adding ${USER_NAME} to group ${group_name}...${RC}"
        "$ESCALATION_TOOL" usermod -aG "$group_name" "$USER_NAME"
        printf "%b\n" "${GREEN}User ${USER_NAME} added to group ${group_name}.${RC}"
    fi
}

setup_groups() {
    print_header "Assign user groups"
    ensure_group "plugdev"
    add_user_to_group "plugdev"
    add_user_to_group "i2c"
    add_user_to_group "disk"
    printf "%b\n" "${YELLOW}Log out and back in for group changes to apply.${RC}"
}

find_desktop_file() {
    find /usr/share/applications "$DESKTOP_DIR" -name "$1" 2>/dev/null | head -n 1
}

prepare_desktop_entry() {
    src=$1
    dest_name=$2
    exec_line=$3

    if [ -f "$src" ]; then
        mkdir -p "$DESKTOP_DIR"
        cp "$src" "$DESKTOP_DIR/$dest_name"
        sed -i "s|^Exec=.*$|Exec=${exec_line}|" "$DESKTOP_DIR/$dest_name"
        printf "%b\n" "${GREEN}Updated $dest_name in ${DESKTOP_DIR}.${RC}"
        return 0
    fi

    return 1
}

configure_desktop_entries() {
    print_header "Configure desktop entries"

    openrgb_desktop=$(find_desktop_file "*openrgb*.desktop")
    if ! prepare_desktop_entry "$openrgb_desktop" "openrgb.desktop" "openrgb --startminimized"; then
        printf "%b\n" "${YELLOW}OpenRGB desktop entry not found.${RC}"
    fi
}

configure_autostart() {
    print_header "Configure autostart"
    printf "%b" "${CYAN}Start OpenRGB on login? (Y/n): ${RC}"
    read -r auto_start
    case "$auto_start" in
        n|N)
            printf "%b\n" "${YELLOW}Skipping autostart configuration.${RC}"
            ;;
        *)
            mkdir -p "$AUTOSTART_DIR"
            for entry in "$AUTOSTART_DIR"/openrgb*.desktop "$AUTOSTART_DIR"/org.openrgb.OpenRGB*.desktop; do
                if [ -f "$entry" ] && [ "$(basename "$entry")" != "$AUTOSTART_ENTRY" ]; then
                    rm -f "$entry"
                fi
            done
            if [ -f "$DESKTOP_DIR/$AUTOSTART_ENTRY" ]; then
                if [ ! -f "$AUTOSTART_DIR/$AUTOSTART_ENTRY" ] || ! cmp -s "$DESKTOP_DIR/$AUTOSTART_ENTRY" "$AUTOSTART_DIR/$AUTOSTART_ENTRY"; then
                    cp "$DESKTOP_DIR/$AUTOSTART_ENTRY" "$AUTOSTART_DIR/"
                fi
            fi
            printf "%b\n" "${GREEN}Autostart configured in ${AUTOSTART_DIR}.${RC}"
            ;;
    esac
}

run_tests() {
    print_header "Verify installation"
    pkill -9 openrgb >/dev/null 2>&1 || true

    if command_exists i2cdetect; then
        printf "%b\n" "${CYAN}Detecting i2c buses...${RC}"
        "$ESCALATION_TOOL" i2cdetect -l | head -n 5
        printf "%b\n" "${GREEN}i2c buses detected.${RC}"
    fi

    if command_exists openrgb; then
        printf "%b\n" "${GREEN}Launching OpenRGB GUI...${RC}"
        openrgb &
    fi
}

print_summary() {
    print_header "Setup complete"
    printf "%b\n" "${GREEN}Completed:${RC}"
    if [ "$OPENRGB_INSTALL_SOURCE" = "flatpak" ]; then
        printf "%b\n" "- Installed OpenRGB via Flatpak"
    else
        printf "%b\n" "- Installed OpenRGB and dependencies"
    fi
    printf "%b\n" "- Installed udev rules and i2c modules"
    printf "%b\n" "- Updated desktop entry for OpenRGB"
    printf "%b\n" "${YELLOW}Next steps:${RC}"
    printf "%b\n" "1. Log out/in so group changes apply."
    printf "%b\n" "2. Start OpenRGB and verify device detection."
}

checkEnv
install_openrgb
install_udev_rules
load_i2c_modules
setup_groups
configure_desktop_entries
configure_autostart
run_tests
print_summary
