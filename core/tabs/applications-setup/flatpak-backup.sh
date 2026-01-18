#! /usr/bin/env bash
# Source: https://www.ctrl.blog/entry/backup-flatpak.html
# The following example script exports a list of your repositories as a list of commands that you can execute to reinstall your Flatpak repositories. You can pipe send the output list to a file as part of your backup script.

set -e

output_file="${1:-/home/oliver/git/TL40-Dots/scripts/pkg-scripts/flatpak-restore.sh}"

echo "# Flatpak Restore Script" > "$output_file"
echo "# Generated on $(date)" >> "$output_file"

# Backup remotes
if flatpak remotes --show-details >/dev/null 2>&1; then
    flatpak remotes --show-details | awk -F'\t' '{
        prio = ($4 != "-" && $4 ~ /^[0-9]+$/) ? " --prio="$4 : ""
        title = ($2 != "") ? " --title=\""$2"\"" : ""
        print "flatpak remote-add --if-not-exists --user \""$1"\" \""$3"\"" prio title
    }' >> "$output_file"
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