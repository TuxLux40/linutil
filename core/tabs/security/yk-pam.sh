#!/bin/sh -e

# Yubico PAM configuration script for sudo and polkit-1 modules
# See https://developers.yubico.com/pam-u2f/ for more information

. ../common-script.sh

CONFIG_DIR="${HOME}/.config/Yubico"
CONFIG_FILE="${CONFIG_DIR}/u2f_keys"

confirmProceeding() {
   printf "%b\n" "${YELLOW}This script will configure Yubico PAM for sudo and polkit-1 modules.${RC}"
   printf "%b\n" "${YELLOW}It will install required packages, enable systemd services,${RC}"
   printf "%b\n" "${YELLOW}generate U2F keys, and update PAM configuration files.${RC}"
   printf "%b\n" "${RED}It is highly recommended to have a separate root shell open for recovery!${RC}"
   printf "%b" "${YELLOW}Do you want to proceed? (y/N): ${RC}"
   read -r response
   if ! echo "$response" | grep -qi "^y"; then
      printf "%b\n" "${YELLOW}Aborting...${RC}"
      exit 0
   fi
}

installYubicoPackages() {
   if command_exists pamu2fcfg; then
      printf "%b\n" "${GREEN}pamu2f is already installed${RC}"
      return
   fi

   printf "%b\n" "${YELLOW}Installing Yubico PAM packages...${RC}"
   case "$PACKAGER" in
      pacman)
         "$ESCALATION_TOOL" "$PACKAGER" -S --noconfirm --needed pamu2f pcsc-lite scdaemon yubico-pam
         ;;
      apt-get|nala)
         "$ESCALATION_TOOL" "$PACKAGER" update >/dev/null 2>&1
         "$ESCALATION_TOOL" "$PACKAGER" install -y libpam-u2f pcsc-lite scdaemon
         ;;
      dnf)
         "$ESCALATION_TOOL" "$PACKAGER" install -y pamu2f pcsc-lite scdaemon
         ;;
      zypper)
         "$ESCALATION_TOOL" "$PACKAGER" install -y pamu2f pcsc-lite scdaemon
         ;;
      apk)
         "$ESCALATION_TOOL" "$PACKAGER" add pamu2f pcsc-lite scdaemon
         ;;
      xbps-install)
         "$ESCALATION_TOOL" "$PACKAGER" -Sy pamu2f pcsc-lite scdaemon
         ;;
      eopkg)
         "$ESCALATION_TOOL" "$PACKAGER" install -y pamu2f pcsc-lite scdaemon
         ;;
      *)
         "$ESCALATION_TOOL" "$PACKAGER" install -y pamu2f pcsc-lite scdaemon
         ;;
   esac
}

enableYubicoServices() {
   if ! command_exists systemctl; then
      printf "%b\n" "${YELLOW}systemctl not found, skipping service enablement${RC}"
      return
   fi

   printf "%b\n" "${YELLOW}Enabling Yubico PAM services...${RC}"
   for svc in pcscd.service scdaemon.service; do
      if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
         "$ESCALATION_TOOL" systemctl enable --now "$svc"
      fi
   done
}

setupConfigDirectory() {
   printf "%b\n" "${YELLOW}Creating configuration directory at ${CONFIG_DIR}...${RC}"
   mkdir -p "$CONFIG_DIR"
   chmod 700 "$CONFIG_DIR"
}

generateYubicoKeys() {
   if [ -f "$CONFIG_FILE" ]; then
      printf "%b\n" "${YELLOW}U2F keys file already exists at ${CONFIG_FILE}${RC}"
      printf "%b" "${YELLOW}Do you want to regenerate? (y/N): ${RC}"
      read -r response
      if ! echo "$response" | grep -qi "^y"; then
         return
      fi
   fi

   printf "%b\n" "${YELLOW}Generating U2F keys (touch your Yubikey when prompted)...${RC}"
   if pamu2fcfg > "${CONFIG_FILE}.tmp"; then
      mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
      chmod 600 "$CONFIG_FILE"
      printf "%b\n" "${GREEN}U2F keys saved to ${CONFIG_FILE}${RC}"
   else
      printf "%b\n" "${RED}Failed to generate U2F keys. Is your Yubikey connected?${RC}"
      rm -f "${CONFIG_FILE}.tmp"
      exit 1
   fi
}

addPamConfig() {
   local pam_config="auth sufficient pam_u2f.so authfile=${CONFIG_FILE} cue"
   local pam_file="$1"
   local pam_name="$2"

   if ! [ -f "$pam_file" ]; then
      printf "%b\n" "${RED}PAM file ${pam_file} not found${RC}"
      return 1
   fi

   # Backup original PAM file
   if [ ! -f "${pam_file}.bak" ]; then
      printf "%b\n" "${YELLOW}Backing up ${pam_file}...${RC}"
      "$ESCALATION_TOOL" cp "$pam_file" "${pam_file}.bak"
   fi

   # Check if config already exists
   if "$ESCALATION_TOOL" grep -q "pam_u2f.so" "$pam_file"; then
      printf "%b\n" "${GREEN}Yubico PAM already configured in ${pam_name}${RC}"
      return 0
   fi

   printf "%b\n" "${YELLOW}Adding Yubico PAM config to ${pam_name}...${RC}"
   "$ESCALATION_TOOL" sed -i "2i ${pam_config}" "$pam_file"
   printf "%b\n" "${GREEN}Updated ${pam_name}${RC}"
}

main() {
   confirmProceeding
   installYubicoPackages
   enableYubicoServices
   setupConfigDirectory
   generateYubicoKeys
   addPamConfig "/etc/pam.d/sudo" "sudo"
   addPamConfig "/etc/pam.d/polkit-1" "polkit-1"
   printf "%b\n" "${GREEN}Yubico PAM configuration complete!${RC}"
}

main