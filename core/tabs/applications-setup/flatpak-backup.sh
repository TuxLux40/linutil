#!/bin/sh -e
# Source: https://www.ctrl.blog/entry/backup-flatpak.html
# Exports user remotes and apps into a restore script inside this repo.

. "$(dirname "$0")/../common-script.sh"

# Default output goes to this repo alongside this script
script_dir="$(dirname "$0")"
output_file="${1:-"$script_dir/flatpak-restore.sh"}"

checkEnv

cat > "$output_file" <<'RESTORE_HDR'
#!/bin/sh -e

SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/../common-script.sh"

checkEnv
checkFlatpak

# Flatpak Restore Script
RESTORE_HDR
echo "# Generated on $(date)" >> "$output_file"

# Backup remotes
if flatpak remotes --show-details >/dev/null 2>&1; then
    flatpak remotes --show-details |
        awk -F'\t' '{
            prio = ($4 != "-" && $4 ~ /^[0-9]+$/) ? " --prio="$4 : ""
            title = ($2 != "") ? " --title=\""$2"\"" : ""
            print "flatpak remote-add --if-not-exists --user \""$1"\" \""$3"\"" prio title
        }' |
        sort -u >> "$output_file"
else
    echo "# No remotes found" >> "$output_file"
fi

# Backup apps
if flatpak list --app --show-details >/dev/null 2>&1; then
    flatpak list --app --show-details |
        awk -F'\t' '{
            split($3, id, "/")
            # $7 is origin/remote for --show-details output
            print "flatpak install --assumeyes --user "$7" \"" id[1] "\""
        }' |
        sort -u >> "$output_file"
else
    echo "# No apps found" >> "$output_file"
fi

echo "Backup saved to $output_file"