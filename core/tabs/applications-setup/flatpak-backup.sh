#! /usr/bin/env bash
# Source: https://www.ctrl.blog/entry/backup-flatpak.html
# The following example script exports a list of your repositories as a list of commands that you can execute to reinstall your Flatpak repositories. You can pipe send the output list to a file as part of your backup script.

set -e

output_file="${1:-/home/oliver/git/TL40-Dots/scripts/pkg-scripts/flatpak-restore.sh}"

echo "# Flatpak Restore Script" > "$output_file"
echo "# Generated on $(date)" >> "$output_file"

# Known flatpakrepo URLs (include GPG keys)
declare -A KNOWN_FLATPAKREPO_URLS=(
    ["flathub"]="https://flathub.org/repo/flathub.flatpakrepo"
    ["flathub-beta"]="https://flathub.org/beta-repo/flathub-beta.flatpakrepo"
    ["gnome-nightly"]="https://nightly.gnome.org/gnome-nightly.flatpakrepo"
    ["kde-applications"]="https://distribute.kde.org/kdeapps.flatpakrepo"
    ["appcenter"]="https://flatpak.elementary.io/repo.flatpakrepo"
)

# Backup remotes
if flatpak remotes --show-details >/dev/null 2>&1; then
    while IFS=$'\t' read -r name title url rest; do
        if [[ -n "${KNOWN_FLATPAKREPO_URLS[$name]}" ]]; then
            echo "flatpak remote-add --if-not-exists --user \"$name\" \"${KNOWN_FLATPAKREPO_URLS[$name]}\"" >> "$output_file"
        else
            echo "flatpak remote-add --if-not-exists --user \"$name\" \"$url\"" >> "$output_file"
        fi
    done < <(flatpak remotes --show-details)
else
    echo "# No remotes found" >> "$output_file"
fi

# Backup apps
if flatpak list --app --show-details >/dev/null 2>&1; then
    flatpak list --app --show-details | awk -F'\t' '{
        split($3, id, "/")
        print "flatpak install --assumeyes --user "$7" \"" id[1] "\""
    }' >> "$output_file"
else
    echo "# No apps found" >> "$output_file"
fi

echo "Backup saved to $output_file"