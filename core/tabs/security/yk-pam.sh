#!/bin/sh -e
# Yubico PAM configuration script for sudo and polkit-1 modules
# See https://developers.yubico.com/pam-u2f/ for more information

. ../common-script.sh

# Variables
HOME=$(eval echo ~"${USER}")
CONFIG_DIR="$HOME/.config/Yubico"
CONFIG_FILE="$CONFIG_DIR/u2f_keys"

# Check environment and set up package manager
checkEnv

# Ask for confirmation before proceeding
printf "%b\n" "${YELLOW}This script will configure Yubico PAM for sudo and polkit-1 modules.${RC}"
printf "%b\n" "${YELLOW}It will install the required packages, enable and start the necessary services,${RC}"
printf "%b\n" "${YELLOW}generate U2F keys, and update the PAM configuration files.${RC}"
printf "%b\n" "${RED}It is highly recommended to have a separate root shell open for recovery purposes!${RC}"
printf "Do you want to proceed? (y/N): "
read -r response
case "$response" in
    [Yy]*)
        ;;
    *)
        printf "%b\n" "${YELLOW}Aborting...${RC}"
        exit 1
        ;;
esac

# Install required packages
installYubicoPAM() {
    printf "%b\n" "${YELLOW}Installing required packages for Yubico PAM...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --noconfirm --needed pam-u2f pcsc-tools pcsclite yubico-pam
            ;;
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" update
            "$ESCALATION_TOOL" "$PACKAGER" install -y libpam-u2f pcscd yubikey-manager
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" install -y pam-u2f pcsc-lite pcsc-tools gnupg2-smime yubikey-manager
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y pam-u2f pcsc-lite pcsc-tools gnupg2 yubikey-manager
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add pam-u2f pcsc-lite pcsc-tools gnupg yubikey-manager
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy pam-u2f pcsclite pcsc-tools gnupg2 yubikey-manager
            ;;
        eopkg)
            "$ESCALATION_TOOL" "$PACKAGER" install -y pam-u2f pcscd yubikey-manager
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            exit 1
            ;;
    esac
}

installYubicoPAM

# Enable and start the services required for Yubico PAM
enableServices() {
    if ! command_exists systemctl; then
        printf "%b\n" "${YELLOW}systemctl not found, skipping service enablement${RC}"
        return
    fi

    printf "%b\n" "${YELLOW}Enabling and starting pcscd service...${RC}"
    "$ESCALATION_TOOL" systemctl enable --now pcscd.service
    sleep 1
    "$ESCALATION_TOOL" systemctl start pcscd.service
    sleep 1
    "$ESCALATION_TOOL" systemctl status pcscd.service
}

enableServices

# Create the configuration directory if it doesn't exist
printf "%b\n" "${YELLOW}Creating configuration directory at %s...${RC}" "$CONFIG_DIR"
mkdir -p "$CONFIG_DIR"

# Generate the U2F keys and save them to the configuration file
printf "%b\n" "${YELLOW}Generating U2F keys and saving to %s...${RC}" "$CONFIG_FILE"
pamu2fcfg > "$CONFIG_FILE"

# Add the PAM configuration for Yubico to the system
# auth sufficient pam_u2f.so authfile=$keyfile cue [prompt=Touch your YubiKey]
printf "%b\n" "${YELLOW}Adding auth line to sudo module...${RC}"
"$ESCALATION_TOOL" sed -i '2i auth sufficient pam_u2f.so authfile='"$CONFIG_FILE"' cue [prompt=Touch your YubiKey]' /etc/pam.d/sudo
printf "%b\n" "${YELLOW}Adding auth line to polkit-1 module...${RC}"
"$ESCALATION_TOOL" sed -i '2i auth sufficient pam_u2f.so authfile='"$CONFIG_FILE"' cue [prompt=Touch your YubiKey]' /etc/pam.d/polkit-1
printf "%b\n" "${GREEN}Done. If you want to revert the changes, you can remove the lines added to /etc/pam.d/sudo and /etc/pam.d/polkit-1 with your text editor.${RC}"