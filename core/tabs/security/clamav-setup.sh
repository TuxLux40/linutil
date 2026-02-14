#!/bin/sh -e

. ../common-script.sh

installClamAV() {
   if command_exists clamscan; then
      printf "%b\n" "${GREEN}ClamAV is already installed${RC}"
      return
   fi

   printf "%b\n" "${YELLOW}Installing ClamAV...${RC}"
   case "$PACKAGER" in
      pacman)
         "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm clamav
         ;;
      apt-get|nala)
         "$ESCALATION_TOOL" "$PACKAGER" update >/dev/null 2>&1
         "$ESCALATION_TOOL" "$PACKAGER" install -y clamav clamav-daemon
         ;;
      dnf)
         "$ESCALATION_TOOL" "$PACKAGER" install -y clamav clamav-update
         ;;
      zypper)
         "$ESCALATION_TOOL" "$PACKAGER" install -y clamav
         ;;
      apk)
         "$ESCALATION_TOOL" "$PACKAGER" add clamav clamav-daemon
         ;;
      xbps-install)
         "$ESCALATION_TOOL" "$PACKAGER" -Sy clamav
         ;;
      eopkg)
         "$ESCALATION_TOOL" "$PACKAGER" install -y clamav
         ;;
      *)
         "$ESCALATION_TOOL" "$PACKAGER" install -y clamav
         ;;
   esac
}

updateSignatures() {
   if ! command_exists freshclam; then
      printf "%b\n" "${YELLOW}freshclam not found, skipping signature update${RC}"
      return
   fi

   printf "%b\n" "${YELLOW}Updating signatures with freshclam...${RC}"
   if ! "$ESCALATION_TOOL" freshclam; then
      printf "%b\n" "${YELLOW}freshclam reported an error. You can rerun it later.${RC}"
   fi
}

enableServices() {
   if ! command_exists systemctl; then
      printf "%b\n" "${YELLOW}systemctl not found, skipping service enablement${RC}"
      return
   fi

   printf "%b\n" "${YELLOW}Enabling available ClamAV services...${RC}"
   enabled=false
   for svc in clamav-daemon.socket clamav-daemon.service clamav-freshclam.service freshclam.service; do
      if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
         "$ESCALATION_TOOL" systemctl enable --now "$svc"
         enabled=true
      fi
   done

   if [ "$enabled" = false ]; then
      printf "%b\n" "${YELLOW}No ClamAV systemd units found to enable${RC}"
   fi
}

installClamUI() {
   printf "%b\n" "${YELLOW}Installing ClamUI (Flatpak)...${RC}"
   checkFlatpak

   if flatpak info io.github.linx_systems.ClamUI >/dev/null 2>&1; then
      printf "%b\n" "${GREEN}ClamUI is already installed${RC}"
      return
   fi

   flatpak install flathub io.github.linx_systems.ClamUI --user -y
}

showStatus() {
   if ! command_exists systemctl; then
      printf "%b\n" "${YELLOW}systemctl not found, skipping service status${RC}"
      return
   fi

   for svc in clamav-daemon.service clamav-freshclam.service freshclam.service; do
      if systemctl list-unit-files "$svc" >/dev/null 2>&1; then
         printf "%b\n" "${YELLOW}Service status ($svc):${RC}"
         systemctl is-active "$svc" >/dev/null 2>&1 && printf "%b\n" "${GREEN}active${RC}" || printf "%b\n" "${YELLOW}inactive${RC}"
         return
      fi
   done
}

printf "%b\n" "${GREEN}Setup complete.${RC}"
printf "%b\n" "${YELLOW}In ClamUI, select the 'System ClamAV' backend and use socket /run/clamav/clamd.ctl if available.${RC}"

checkEnv

installClamAV
updateSignatures
enableServices
installClamUI
showStatus