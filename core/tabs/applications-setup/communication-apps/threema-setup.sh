#!/bin/sh -e

. ../../common-script.sh

installThreema() {
    if ! command_exists threema-web-desktop; then
        printf "%b\n" "${YELLOW}Installing Threema Desktop...${RC}"
        case "$PACKAGER" in
            pacman)
                # Try official AUR package first
                if "$ESCALATION_TOOL" "$PACKAGER" -Si threema-web-desktop >/dev/null 2>&1; then
                    "$ESCALATION_TOOL" "$PACKAGER" -S --noconfirm threema-web-desktop
                else
                    checkAURHelper
                    if "$AUR_HELPER" -S --needed --noconfirm threema-web-desktop 2>/dev/null; then
                        true
                    else
                        # Fall back to Flatpak
                        checkFlatpak
                        flatpak install -y flathub ch.threema.threema-web-desktop
                    fi
                fi
                ;;
            apt-get|nala|dnf|zypper|eopkg|apk|xbps-install)
                # Fallback to Flatpak for these
                checkFlatpak
                flatpak install -y flathub ch.threema.threema-web-desktop
                ;;
            *)
                printf "%b\n" "${RED}Unsupported package manager: "$PACKAGER"${RC}"
                exit 1
                ;;
        esac
    else
        printf "%b\n" "${GREEN}Threema Desktop is already installed.${RC}"
    fi
}

checkEnv
checkEscalationTool
checkAURHelper
installThreema
