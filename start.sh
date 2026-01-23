#!/bin/sh -e

# Prevent execution if this script was only partially downloaded
{
rc='\033[0m'
red='\033[0;31m'

check() {
    exit_code=$1
    message=$2

    if [ "$exit_code" -ne 0 ]; then
        printf '%sERROR: %s%s\n' "$red" "$message" "$rc"
        exit 1
    fi

    unset exit_code
    unset message
}

if command -v /usr/bin/linutil >/dev/null 2>&1; then
    /usr/bin/linutil "$@"
    check $? "Starting installed linutil"
    exit 0
fi

echo "linutil ist nicht installiert. Bitte führe ./install.sh aus oder ./update.sh für System-Installation in /usr/bin."
exit 1
} # End of wrapping
