#!/bin/sh -e

SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/../../common-script.sh"

checkEnv
checkEscalationTool
checkCommandRequirements "git"

GHOST_REPO="https://github.com/GH05TCREW/ghostcrew.git"
GHOST_PARENT_DIR="$HOME/git"
GHOST_DIR="${1:-"$GHOST_PARENT_DIR/ghostcrew"}"

# Ensure target parent directory exists
mkdir -p "$GHOST_PARENT_DIR"

if [ ! -d "$GHOST_DIR/.git" ]; then
	printf "%b\n" "${YELLOW}Cloning ghostcrew into $GHOST_DIR...${RC}"
	git clone "$GHOST_REPO" "$GHOST_DIR"
else
	printf "%b\n" "${CYAN}Updating ghostcrew in $GHOST_DIR...${RC}"
	cd "$GHOST_DIR"
	git pull --ff-only
fi

cd "$GHOST_DIR"
printf "%b\n" "${YELLOW}Running setup script...${RC}"
if [ -x ./scripts/setup.sh ]; then
	./scripts/setup.sh
else
	sh ./scripts/setup.sh
fi