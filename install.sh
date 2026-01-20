#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Building linutil...${NC}"
cargo build --release

BINARY="./target/release/linutil"
INSTALL_PATH="/usr/local/bin/linutil"

if [ ! -f "$BINARY" ]; then
    echo -e "${RED}Error: Binary not found at $BINARY${NC}"
    exit 1
fi

echo -e "${YELLOW}Installing to $INSTALL_PATH...${NC}"

if [ "$EUID" -ne 0 ]; then
    echo -e "${YELLOW}Requesting sudo privileges to install to $INSTALL_PATH${NC}"
    sudo cp "$BINARY" "$INSTALL_PATH"
else
    cp "$BINARY" "$INSTALL_PATH"
fi

chmod +x "$INSTALL_PATH"

echo -e "${GREEN}✓ Installation successful!${NC}"
echo -e "${GREEN}You can now run: ${YELLOW}linutil${GREEN}${NC}"

# Verify installation
if command -v linutil &> /dev/null; then
    linutil --version || true
else
    echo -e "${YELLOW}Note: Make sure /usr/local/bin is in your \$PATH${NC}"
fi
