#!/bin/sh -e

. ../../common-script.sh

installSession() {
    if ! command_exists session-desktop; then
        printf "%b\n" "${YELLOW}Installing Session Desktop...${RC}"
        case "$PACKAGER" in
            pacman)
                # Try official repos first
                if "$ESCALATION_TOOL" "$PACKAGER" -Si session-desktop >/dev/null 2>&1; then
                    "$ESCALATION_TOOL" "$PACKAGER" -S --noconfirm session-desktop
                else
                    # Fallback to Flatpak
                    checkFlatpak
                    flatpak install -y flathub network.loki.Session
                fi
                ;;
            apt-get|nala)
                # Try snap (Session is on snap)
                if command_exists snap; then
                    "$ESCALATION_TOOL" snap install session
                else
                    # Fallback to Flatpak
                    checkFlatpak
                    flatpak install -y flathub network.loki.Session
                fi
                ;;
            dnf|zypper|eopkg|apk|xbps-install)
                # Fallback to Flatpak for these
                checkFlatpak
                flatpak install -y flathub network.loki.Session
                ;;
            *)
                printf "%b\n" "${RED}Unsupported package manager: "$PACKAGER"${RC}"
                exit 1
                ;;
        esac
    else
        printf "%b\n" "${GREEN}Session Desktop is already installed.${RC}"
    fi
}

checkEnv
checkEscalationTool
installSession
