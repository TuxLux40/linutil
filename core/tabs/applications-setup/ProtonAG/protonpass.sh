#!/bin/sh -e

. ../../common-script.sh

APP_NAME="Proton Pass"

install_flatpak() {
    if command_exists flatpak; then
        if flatpak remote-list | grep -qi flathub; then
            if flatpak info com.proton.pass >/dev/null 2>&1; then
                printf "%b\n" "${GREEN}${APP_NAME} (Flatpak) is already installed.${RC}"
            else
                printf "%b\n" "${YELLOW}Installing ${APP_NAME} via Flatpak...${RC}"
                if flatpak install -y flathub com.proton.pass; then
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

install_arch() {
    if [ -n "$AUR_HELPER" ]; then
        printf "%b\n" "${YELLOW}Installing ${APP_NAME} from AUR (proton-pass-bin)...${RC}"
        "$AUR_HELPER" -S --needed --noconfirm proton-pass-bin
        return 0
    fi
    return 1
}

main() {
    if command_exists proton-pass; then
        printf "%b\n" "${GREEN}${APP_NAME} is already installed.${RC}"
        exit 0
    fi

    checkEnv
    checkEscalationTool
    checkAURHelper

    # 1) Arch AUR (official binary package in AUR)
    if install_arch; then
        printf "%b\n" "${GREEN}${APP_NAME} installation completed.${RC}"
        exit 0
    fi

    # 2) Flatpak as fallback
    if install_flatpak; then
        printf "%b\n" "${GREEN}${APP_NAME} installation completed.${RC}"
        exit 0
    fi

    printf "%b\n" "${RED}Could not automatically install ${APP_NAME}.${RC}"
    printf "%b\n" "${YELLOW}Please download the appropriate package manually from https://proton.me/download and install it (or enable Flatpak/Flathub).${RC}"
    exit 1
}

main
