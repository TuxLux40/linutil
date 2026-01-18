#!/bin/sh -e

. ../../common-script.sh

installKeybase() {
    if ! command_exists keybase && ! command_exists Keybase && ! command_exists run_keybase; then
        printf "%b\n" "${YELLOW}Installing Keybase...${RC}"
        case "$PACKAGER" in
            apt-get|nala)
                # Debian/Ubuntu has keybase in repo, try first
                if "$ESCALATION_TOOL" apt-cache policy keybase >/dev/null 2>&1; then
                    "$ESCALATION_TOOL" "$PACKAGER" install -y keybase
                elif [ "$ARCH" = "x86_64" ]; then
                    # Fall back to official .deb
                    curl -fsSL -o keybase_amd64.deb https://prerelease.keybase.io/keybase_amd64.deb
                    "$ESCALATION_TOOL" "$PACKAGER" install -y ./keybase_amd64.deb || "$ESCALATION_TOOL" dpkg -i ./keybase_amd64.deb
                    rm -f keybase_amd64.deb
                else
                    printf "%b\n" "${RED}Keybase requires x86_64 architecture.${RC}"
                    exit 1
                fi
                ;;
            dnf)
                # Try official Fedora repos first
                if "$ESCALATION_TOOL" "$PACKAGER" info keybase >/dev/null 2>&1; then
                    "$ESCALATION_TOOL" "$PACKAGER" install -y keybase
                elif [ "$ARCH" = "x86_64" ]; then
                    # Fall back to official .rpm
                    curl -fsSL -o keybase_amd64.rpm https://prerelease.keybase.io/keybase_amd64.rpm
                    "$ESCALATION_TOOL" "$PACKAGER" install -y ./keybase_amd64.rpm
                    rm -f keybase_amd64.rpm
                else
                    printf "%b\n" "${RED}Keybase requires x86_64 architecture.${RC}"
                    exit 1
                fi
                ;;
            pacman)
                # Try official community/extra repos first
                if "$ESCALATION_TOOL" "$PACKAGER" -Si keybase >/dev/null 2>&1; then
                    "$ESCALATION_TOOL" "$PACKAGER" -S --noconfirm keybase
                else
                    # Fall back to AUR (keybase-bin is pre-built binary)
                    checkAURHelper
                    "$AUR_HELPER" -S --needed --noconfirm keybase-bin
                fi
                ;;
            zypper)
                # Try official repos first
                if "$ESCALATION_TOOL" "$PACKAGER" info keybase >/dev/null 2>&1; then
                    "$ESCALATION_TOOL" "$PACKAGER" install -y keybase
                elif [ "$ARCH" = "x86_64" ]; then
                    # Fall back to official .rpm
                    curl -fsSL -o keybase_amd64.rpm https://prerelease.keybase.io/keybase_amd64.rpm
                    "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install ./keybase_amd64.rpm
                    rm -f keybase_amd64.rpm
                else
                    printf "%b\n" "${RED}Keybase requires x86_64 architecture.${RC}"
                    exit 1
                fi
                ;;
            xbps-install)
                # Try official repos
                if "$ESCALATION_TOOL" "$PACKAGER" -S keybase >/dev/null 2>&1; then
                    "$ESCALATION_TOOL" "$PACKAGER" -Sy keybase
                else
                    printf "%b\n" "${RED}Keybase not available via xbps repos.${RC}"
                    exit 1
                fi
                ;;
            apk|eopkg)
                printf "%b\n" "${RED}Keybase not available via $PACKAGER on this system.${RC}"
                exit 1
                ;;
            *)
                printf "%b\n" "${RED}Unsupported package manager: "$PACKAGER"${RC}"
                exit 1
                ;;
        esac
    else
        printf "%b\n" "${GREEN}Keybase is already installed.${RC}"
    fi
}

postInstallHint() {
    if command_exists run_keybase; then
        printf "%b\n" "${CYAN}You can start Keybase services with: run_keybase${RC}"
    fi
}

checkEnv
checkEscalationTool
checkAURHelper
installKeybase
postInstallHint
