#!/bin/sh -e

SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/../common-script.sh"

checkEnv
checkFlatpak

# Flatpak Restore Script
# Generated on Fr 23. Jan 23:28:28 CET 2026
flatpak remote-add --if-not-exists --user "flathub" "https://dl.flathub.org/repo/" --title="Flathub"
flatpak install --assumeyes --user flathub "com.gitlab.davem.ClamTk"
flatpak install --assumeyes --user flathub "com.jgraph.drawio.desktop"
flatpak install --assumeyes --user flathub "dev.deedles.Trayscale"
flatpak install --assumeyes --user flathub "io.github.adrienverge.PhotoCollage"
flatpak install --assumeyes --user flathub "io.github.brunofin.Cohesion"
