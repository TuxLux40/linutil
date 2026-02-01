#!/bin/sh -e

. ../../common-script.sh

installMatrix() {
    if ! command_exists element-desktop; then
        printf "%b\n" "${YELLOW}Installing Element (Matrix client)...${RC}"
        case "$PACKAGER" in
            pacman)
                # Try official repos first
                if "$ESCALATION_TOOL" "$PACKAGER" -Si element-desktop >/dev/null 2>&1; then
                    "$ESCALATION_TOOL" "$PACKAGER" -S --noconfirm element-desktop
                else
                    # Fall back to Flatpak
                    checkFlatpak
                    flatpak install -y flathub im.riot.Riot
                fi
                ;;
            apt-get|nala)
                # Try official Debian/Ubuntu repos
                if "$ESCALATION_TOOL" apt-cache policy element-desktop >/dev/null 2>&1; then
                    "$ESCALATION_TOOL" "$PACKAGER" install -y element-desktop
                else
                    # Fall back to Flatpak
                    checkFlatpak
                    flatpak install -y flathub im.riot.Riot
                fi
                ;;
            dnf)
                # Try official Fedora repos
                if "$ESCALATION_TOOL" "$PACKAGER" info element-desktop >/dev/null 2>&1; then
                    "$ESCALATION_TOOL" "$PACKAGER" install -y element-desktop
                else
                    # Fall back to Flatpak
                    checkFlatpak
                    flatpak install -y flathub im.riot.Riot
                fi
                ;;
            zypper)
                # Try official openSUSE repos
                if "$ESCALATION_TOOL" "$PACKAGER" info element-desktop >/dev/null 2>&1; then
                    "$ESCALATION_TOOL" "$PACKAGER" install -y element-desktop
                else
                    # Fall back to Flatpak
                    checkFlatpak
                    flatpak install -y flathub im.riot.Riot
                fi
                ;;
            apk|eopkg|xbps-install)
                # Fallback to Flatpak for these
                checkFlatpak
                flatpak install -y flathub im.riot.Riot
                ;;
            *)
                printf "%b\n" "${RED}Unsupported package manager: "$PACKAGER"${RC}"
                exit 1
                ;;
        esac
    else
        printf "%b\n" "${GREEN}Element is already installed.${RC}"
    fi
}

checkEnv
checkEscalationTool
installMatrix
