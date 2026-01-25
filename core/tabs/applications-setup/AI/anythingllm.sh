#!/bin/sh -e

SCRIPT_DIR="$(dirname "$0")"
. "$SCRIPT_DIR/../../common-script.sh"

checkEnv
checkCommandRequirements "git node npm"

PARENT_DIR="$HOME/git"
TARGET_DIR="${1:-"$PARENT_DIR/anythingllm"}"
REPO_URL="https://github.com/Mintplex-Labs/anything-llm"

mkdir -p "$PARENT_DIR"

if [ ! -d "$TARGET_DIR/.git" ]; then
	printf "%b\n" "${YELLOW}Cloning AnythingLLM into $TARGET_DIR...${RC}"
	git clone "$REPO_URL" "$TARGET_DIR"
else
	printf "%b\n" "${CYAN}Updating AnythingLLM in $TARGET_DIR...${RC}"
	(cd "$TARGET_DIR" && git pull --ff-only)
fi

printf "%b\n" "${YELLOW}Installing dependencies (npm install)...${RC}"
(cd "$TARGET_DIR" && npm install)

printf "%b\n" "${GREEN}AnythingLLM bare-metal setup complete.${RC}"
printf "%b\n" "${CYAN}Start it with:${RC}"
printf "%b\n" "${CYAN}  cd $TARGET_DIR && npm run start${RC}"
