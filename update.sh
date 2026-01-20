#!/bin/bash
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Updating linutil from fork...${NC}"

# Check for uncommitted changes
if ! git diff-index --quiet HEAD -- 2>/dev/null; then
    echo -e "${RED}Error: You have uncommitted changes!${NC}"
    echo -e "${YELLOW}Please commit or stash your changes first:${NC}"
    echo "  git status"
    echo "  git add -A && git commit -m 'your message'"
    echo "  OR: git stash"
    exit 1
fi

git pull

echo -e "${YELLOW}Building and installing...${NC}"
cargo install --path ./tui

echo -e "${GREEN}✓ Update successful!${NC}"
linutil --help > /dev/null 2>&1 && echo -e "${GREEN}linutil is ready to use${NC}"
