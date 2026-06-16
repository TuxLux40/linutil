#!/bin/sh -e

. ../../common-script.sh

RAZER_REPO="https://github.com/TuxLux40/razer-leviathan-v2x-linux-fix.git"

applyRazerFix() {
    TMPDIR="$(mktemp -d)"
    printf "%b\n" "${YELLOW}Cloning Razer Leviathan V2 X fix...${RC}"
    git clone --depth 1 "$RAZER_REPO" "$TMPDIR/razer-fix"
    printf "%b\n" "${YELLOW}Applying fix — device must be plugged in via USB-C...${RC}"
    bash "$TMPDIR/razer-fix/install.sh"
    rm -rf "$TMPDIR"
}

checkEnv
applyRazerFix
