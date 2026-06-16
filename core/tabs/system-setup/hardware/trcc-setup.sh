#!/bin/sh -e

. ../../common-script.sh

TRCC_REPO="https://github.com/tuxlux40/thermalright-trcc-linux.git"
TRCC_DIR="$HOME/.local/share/trcc-linux"

installTRCC() {
    if [ -d "$TRCC_DIR/.git" ]; then
        printf "%b\n" "${YELLOW}Updating existing TRCC clone at $TRCC_DIR...${RC}"
        git -C "$TRCC_DIR" pull --ff-only
    else
        printf "%b\n" "${YELLOW}Cloning TRCC Linux into $TRCC_DIR...${RC}"
        mkdir -p "$(dirname "$TRCC_DIR")"
        git clone --depth 1 "$TRCC_REPO" "$TRCC_DIR"
    fi
    printf "%b\n" "${YELLOW}Running TRCC installer...${RC}"
    "$ESCALATION_TOOL" bash "$TRCC_DIR/install.sh"
}

checkEnv
checkEscalationTool
installTRCC
