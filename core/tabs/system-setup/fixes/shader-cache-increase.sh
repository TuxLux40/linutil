#!/usr/bin/env bash

# AMD Vulkan and Mesa Configuration Script
# Adds AMD-specific environment variables to /etc/environment

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Error: This script must be run as root (use sudo)${NC}"
    exit 1
fi

# Backup /etc/environment
BACKUP_FILE="/etc/environment.backup.$(date +%Y%m%d_%H%M%S)"
echo -e "${YELLOW}Creating backup: ${BACKUP_FILE}${NC}"
cp /etc/environment "$BACKUP_FILE"

# Define the lines to add
AMD_CONFIG="
# Enforces RADV Vulkan implementation
AMD_VULKAN_ICD=RADV

# Increase AMD's shader cache size to 12GB
MESA_SHADER_CACHE_MAX_SIZE=12G"

# Check if the configuration already exists
if grep -q "AMD_VULKAN_ICD=RADV" /etc/environment; then
    echo -e "${YELLOW}AMD Vulkan configuration already exists in /etc/environment${NC}"
    echo -e "${YELLOW}Skipping to avoid duplicates${NC}"
    exit 0
fi

# Add configuration to /etc/environment
echo -e "${GREEN}Adding AMD Vulkan configuration to /etc/environment...${NC}"
echo "$AMD_CONFIG" >> /etc/environment

echo -e "${GREEN}✓ Configuration added successfully!${NC}"
echo -e "${YELLOW}Note: You need to log out and log back in (or reboot) for changes to take effect${NC}"
echo ""
echo "Added configuration:"
echo "$AMD_CONFIG"
