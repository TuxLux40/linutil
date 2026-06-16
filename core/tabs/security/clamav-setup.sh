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

configureClamAV() {
   CLAMD_CONF=""
   for f in /etc/clamav/clamd.conf /etc/clamd.d/scan.conf /etc/clamd.conf; do
      if [ -f "$f" ]; then
         CLAMD_CONF="$f"
         break
      fi
   done

   if [ -z "$CLAMD_CONF" ]; then
      printf "%b\n" "${YELLOW}clamd.conf not found — skipping resource limit configuration.${RC}"
      return
   fi

   printf "%b\n" "${YELLOW}Applying resource limits to $CLAMD_CONF...${RC}"
   for setting in \
      "MaxThreads 2" \
      "MaxRecursion 10" \
      "MaxFiles 10000" \
      "MaxFileSize 25M" \
      "MaxScanSize 100M" \
      "ConcurrentDatabaseReload no" \
      "OnAccessScanning no"; do
      key="${setting%% *}"
      "$ESCALATION_TOOL" sed -i "/^#*[[:space:]]*${key}[[:space:]]/d" "$CLAMD_CONF"
      printf '%s\n' "$setting" | "$ESCALATION_TOOL" tee -a "$CLAMD_CONF" >/dev/null
   done
   printf "%b\n" "${GREEN}Resource limits applied.${RC}"
}

enableServices() {
   if ! command_exists systemctl; then
      printf "%b\n" "${YELLOW}systemctl not found, skipping service enablement${RC}"
      return
   fi

   printf "%b\n" "${YELLOW}Enabling ClamAV services...${RC}"

   # Enable signature updater (freshclam)
   for svc in clamav-freshclam.service freshclam.service; do
      if systemctl list-unit-files 2>/dev/null | grep -q "^$svc"; then
         "$ESCALATION_TOOL" systemctl enable --now "$svc"
         printf "%b\n" "${GREEN}Enabled $svc.${RC}"
         break
      fi
   done

   # Enable the socket daemon — it loads the DB once and serves on-demand scan
   # requests efficiently. On-access scanning (clamonacc) is disabled via clamd.conf
   # so the daemon is idle and uses no CPU until a scan is requested.
   for svc in clamav-daemon.service clamd.service; do
      if systemctl list-unit-files 2>/dev/null | grep -q "^$svc"; then
         "$ESCALATION_TOOL" systemctl enable --now "$svc"
         printf "%b\n" "${GREEN}Enabled $svc.${RC}"
         break
      fi
   done
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

checkEnv

installClamAV
updateSignatures
configureClamAV
enableServices
installClamUI
showStatus

printf "%b\n" "${GREEN}Setup complete.${RC}"
printf "%b\n" "${YELLOW}In ClamUI choose the 'System ClamAV' backend and use socket /run/clamav/clamd.ctl.${RC}"
printf "%b\n" "${YELLOW}The daemon is idle between scans. On-access scanning (clamonacc) is disabled — that was the CPU hog.${RC}"