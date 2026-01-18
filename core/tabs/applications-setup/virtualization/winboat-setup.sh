#!/bin/sh -e

. ../../common-script.sh

APP_NAME="Winboat"
AUR_PKG_PRIMARY="winboat-bin"
AUR_PKG_FALLBACK="winboat"

install_arch() {
    if [ -z "$AUR_HELPER" ]; then
        printf "%b\n" "${RED}No AUR helper configured. Please install $APP_NAME manually or set AUR_HELPER.${RC}"
        return 1
    fi

    printf "%b\n" "${YELLOW}Installing ${APP_NAME} from AUR (${AUR_PKG_PRIMARY} → ${AUR_PKG_FALLBACK})...${RC}"
    if "$AUR_HELPER" -S --needed --noconfirm "$AUR_PKG_PRIMARY"; then
        return 0
    fi

    printf "%b\n" "${YELLOW}Fallback: trying ${AUR_PKG_FALLBACK}...${RC}"
    "$AUR_HELPER" -S --needed --noconfirm "$AUR_PKG_FALLBACK"
}

main() {
    if command_exists winboat; then
        printf "%b\n" "${GREEN}${APP_NAME} is already installed.${RC}"
        exit 0
    fi

    checkEnv
    checkEscalationTool
    checkAURHelper

    case "$PACKAGER" in
        pacman)
            if install_arch; then
                printf "%b\n" "${GREEN}${APP_NAME} installation completed.${RC}"
                exit 0
            fi
            ;;
        *)
            printf "%b\n" "${YELLOW}No automatic installer available for your distribution.${RC}"
            printf "%b\n" "${YELLOW}Please install ${APP_NAME} manually (e.g., via AppImage/official repo if available).${RC}"
            ;;
    esac

    printf "%b\n" "${RED}Could not automatically install ${APP_NAME}.${RC}"
    exit 1
}

main
