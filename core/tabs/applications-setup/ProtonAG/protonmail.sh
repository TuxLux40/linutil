#!/bin/sh -e

. ../../common-script.sh

APP_NAME="Proton Mail"

# Best-effort installer: prefers official packages where available

install_flatpak() {
    if command_exists flatpak; then
        if flatpak remote-list | grep -qi flathub; then
            if flatpak info com.proton.mail >/dev/null 2>&1; then
                printf "%b\n" "${GREEN}${APP_NAME} (Flatpak) is already installed.${RC}"
            else
                printf "%b\n" "${YELLOW}Installing ${APP_NAME} via Flatpak (if available)...${RC}"
                if flatpak install -y flathub com.proton.mail; then
                    return 0
                else
                    printf "%b\n" "${RED}Flatpak installation failed or package not available.${RC}"
                fi
            fi
        else
            printf "%b\n" "${YELLOW}Flathub is not configured. Skipping Flatpak.${RC}"
        fi
    fi
    return 1
}

install_deb_rpm() {
    arch="$(uname -m)"
    tmp_dir=$(mktemp -d)
    cd "$tmp_dir"

    case "$PACKAGER" in
        apt-get|nala)
            url="https://proton.me/download/mail/linux/ProtonMail-desktop.deb"
            out="protonmail-desktop.deb"
            ;;
        dnf|zypper)
            url="https://proton.me/download/mail/linux/ProtonMail-desktop.rpm"
            out="protonmail-desktop.rpm"
            ;;
        *)
            return 1
            ;;
    esac

    printf "%b\n" "${YELLOW}Downloading ${APP_NAME} package (${arch})...${RC}"
    if ! curl -fL "$url" -o "$out"; then
        printf "%b\n" "${RED}Download failed. Please check the URL manually.${RC}"
        rm -rf "$tmp_dir"
        return 1
    fi

    printf "%b\n" "${YELLOW}Installing ${APP_NAME}...${RC}"
    case "$PACKAGER" in
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" install -y "./$out"
            ;;
        dnf|zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y "./$out"
            ;;
    esac

    rm -rf "$tmp_dir"
    return 0
}

install_arch() {
    if [ -n "$AUR_HELPER" ]; then
        printf "%b\n" "${YELLOW}Installing ${APP_NAME} from AUR (proton-mail-desktop-bin)...${RC}"
        "$AUR_HELPER" -S --needed --noconfirm proton-mail-desktop-bin
        return 0
    fi
    return 1
}

main() {
    if command_exists proton-mail || command_exists ProtonMail || command_exists "Proton Mail"; then
        printf "%b\n" "${GREEN}${APP_NAME} is already installed.${RC}"
        exit 0
    fi

    checkEnv
    checkEscalationTool
    checkAURHelper

    # 1) Official packages (deb/rpm) first
    if install_deb_rpm; then
        printf "%b\n" "${GREEN}${APP_NAME} installation completed.${RC}"
        exit 0
    fi

    # 2) Arch AUR
    if install_arch; then
        printf "%b\n" "${GREEN}${APP_NAME} installation completed.${RC}"
        exit 0
    fi

    # 3) Flatpak as fallback
    if install_flatpak; then
        printf "%b\n" "${GREEN}${APP_NAME} installation completed.${RC}"
        exit 0
    fi

    printf "%b\n" "${RED}Could not automatically install ${APP_NAME}.${RC}"
    printf "%b\n" "${YELLOW}Please download the appropriate package manually from https://proton.me/download and install it.${RC}"
    exit 1
}

main
