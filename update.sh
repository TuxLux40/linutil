#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Updating linutil (system binary)...${NC}"

# Auto-stash local changes to avoid failures
STASHED=0
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo -e "${YELLOW}Working tree dirty -> stashing changes${NC}"
    git stash -u
    STASHED=1
fi

git pull --ff-only

echo -e "${YELLOW}Building release binary...${NC}"
cargo build --release

BIN_PATH="./target/release/linutil"
INSTALL_PATH="/usr/bin/linutil"

if [ ! -f "$BIN_PATH" ]; then
    echo -e "${RED}Error: Binary not found at $BIN_PATH${NC}"
    [ "$STASHED" -eq 1 ] && { echo -e "${YELLOW}Restoring stashed changes...${NC}"; git stash pop || true; }
    exit 1
fi

echo -e "${YELLOW}Installing to $INSTALL_PATH...${NC}"
if [ "$EUID" -ne 0 ]; then
    sudo cp "$BIN_PATH" "$INSTALL_PATH"
else
    cp "$BIN_PATH" "$INSTALL_PATH"
fi
sudo chmod +x "$INSTALL_PATH" || chmod +x "$INSTALL_PATH"

if command -v linutil >/dev/null 2>&1; then
    echo -e "${GREEN}✓ System binary installed: $(command -v linutil)${NC}"
else
    echo -e "${RED}linutil not found in PATH after install.${NC}"
    echo -e "${YELLOW}Please ensure /usr/bin is in your PATH (standard).${NC}"
fi

if [ "$STASHED" -eq 1 ]; then
    echo -e "${YELLOW}Restoring stashed changes...${NC}"
    git stash pop || true
fi

echo -e "${GREEN}✓ Update complete.${NC}"
