#!/bin/sh -e
# shellcheck disable=SC3040

. ../common-script.sh

# AppArmor Boot Parameter Setup
# SAFELY adds AppArmor to GRUB boot parameters
# Includes comprehensive validation and recovery mechanisms

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    printf "%b\n" "${RED}Error: This script must be run as root (use sudo)${RC}"
    exit 1
fi

# Trap errors for cleanup
trap 'handle_error' ERR

handle_error() {
    printf "%b\n" "${RED}ERROR: Script failed${RC}"
    printf "%b\n" "${YELLOW}If GRUB was modified, your system might not boot.${RC}"
    printf "%b\n" "${YELLOW}Restore from backup if needed.${RC}"
    exit 1
}

# WARNING: Get explicit confirmation
printf "%b\n" "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
printf "%b\n" "${RED}⚠️  WARNING: APPARMOR MAY CAUSE BOOT FAILURE ⚠️${RC}"
printf "%b\n" "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
printf "%b\n" "${YELLOW}This script will modify GRUB boot parameters.${RC}"
printf "%b\n" "${YELLOW}If something goes wrong, your system may not boot.${RC}"
printf "%b\n" "${YELLOW}Be especially careful if you have custom GRUB configurations or encrypted disks, as it can lock you out of your system.${RC}"
printf "\n"
printf "%b\n" "${YELLOW}Before continuing, ensure you have:${RC}"
printf "%b\n" "  1. Full system backup"
printf "%b\n" "  2. Live USB/recovery media available"
printf "%b\n" "  3. Knowledge to restore from backup"
printf "\n"

read -p "Type 'I UNDERSTAND THE RISKS' to continue: " confirmation

if [ "$confirmation" != "I UNDERSTAND THE RISKS" ]; then
    printf "%b\n" "${RED}Aborted by user${RC}"
    exit 1
fi
printf "\n"

GRUB_CONFIG="/etc/default/grub"

# Check if GRUB config exists
if [ ! -f "$GRUB_CONFIG" ]; then
    printf "%b\n" "${RED}Error: $GRUB_CONFIG not found. Is GRUB installed?${RC}"
    exit 1
fi

# Backup the original GRUB config
BACKUP_FILE="${GRUB_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
printf "%b\n" "${YELLOW}Creating backup: ${BACKUP_FILE}${RC}"
cp "$GRUB_CONFIG" "$BACKUP_FILE"

# Check if AppArmor is already in boot parameters
if grep -q 'apparmor=1' "$GRUB_CONFIG" && grep -q 'security=apparmor' "$GRUB_CONFIG"; then
    printf "%b\n" "${YELLOW}✓ AppArmor boot parameters already configured${RC}"
    exit 0
fi

printf "%b\n" "${GREEN}Adding AppArmor to boot parameters...${RC}"

# Get current GRUB_CMDLINE_LINUX_DEFAULT value
CURRENT_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_CONFIG" 2>/dev/null | cut -d'"' -f2 || echo "")

if [ -z "$CURRENT_CMDLINE" ]; then
    printf "%b\n" "${RED}Error: Could not read GRUB_CMDLINE_LINUX_DEFAULT${RC}"
    exit 1
fi

# Check if we need to add AppArmor parameters
NEEDS_UPDATE=false
NEW_CMDLINE="$CURRENT_CMDLINE"

if [[ ! "$CURRENT_CMDLINE" =~ apparmor=1 ]]; then
    NEW_CMDLINE="$NEW_CMDLINE apparmor=1"
    NEEDS_UPDATE=true
fi

if [[ ! "$CURRENT_CMDLINE" =~ security=apparmor ]]; then
    NEW_CMDLINE="$NEW_CMDLINE security=apparmor"
    NEEDS_UPDATE=true
fi

if [ "$NEEDS_UPDATE" = false ]; then
    printf "%b\n" "${YELLOW}✓ AppArmor parameters already present${RC}"
    exit 0
fi

# Trim leading/trailing spaces
NEW_CMDLINE=$(printf '%s' "$NEW_CMDLINE" | xargs)

printf "%b\n" "${YELLOW}Current boot parameters:${RC} $CURRENT_CMDLINE"
printf "%b\n" "${YELLOW}New boot parameters:${RC} $NEW_CMDLINE"

# Update the GRUB config using a temp file for safety
TEMP_CONFIG=$(mktemp)
trap "rm -f '$TEMP_CONFIG'" EXIT

# Use a safer method to replace the line
sed "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_CMDLINE\"|" "$GRUB_CONFIG" > "$TEMP_CONFIG"

# Verify the sed worked
if ! grep -q "apparmor=1" "$TEMP_CONFIG" || ! grep -q "security=apparmor" "$TEMP_CONFIG"; then
    printf "%b\n" "${RED}ERROR: Failed to update GRUB config${RC}"
    exit 1
fi

# Apply the changes
cp "$TEMP_CONFIG" "$GRUB_CONFIG"

printf "%b\n" "${GREEN}✓ GRUB config updated${RC}"

# Verify the change
if ! grep -q 'apparmor=1' "$GRUB_CONFIG" || ! grep -q 'security=apparmor' "$GRUB_CONFIG"; then
    printf "%b\n" "${RED}ERROR: Failed to update GRUB config properly${RC}"
    printf "%b\n" "${YELLOW}Restoring backup...${RC}"
    cp "$BACKUP_FILE" "$GRUB_CONFIG"
    printf "%b\n" "${GREEN}✓ Backup restored${RC}"
    exit 1
fi

# Update GRUB with proper error checking
printf "%b\n" "${YELLOW}Updating GRUB bootloader...${RC}"

GRUB_UPDATED=false

if command -v grub-mkconfig >/dev/null 2>&1; then
    if grub-mkconfig -o /boot/grub/grub.cfg; then
        GRUB_UPDATED=true
    else
        printf "%b\n" "${RED}ERROR: grub-mkconfig failed${RC}"
        cp "$BACKUP_FILE" "$GRUB_CONFIG"
        exit 1
    fi
elif command -v update-grub >/dev/null 2>&1; then
    if update-grub; then
        GRUB_UPDATED=true
    else
        printf "%b\n" "${RED}ERROR: update-grub failed${RC}"
        cp "$BACKUP_FILE" "$GRUB_CONFIG"
        exit 1
    fi
else
    printf "%b\n" "${RED}ERROR: Neither grub-mkconfig nor update-grub found${RC}"
    cp "$BACKUP_FILE" "$GRUB_CONFIG"
    exit 1
fi

if [ "$GRUB_UPDATED" = false ]; then
    printf "%b\n" "${RED}ERROR: GRUB update failed${RC}"
    cp "$BACKUP_FILE" "$GRUB_CONFIG"
    exit 1
fi

printf "%b\n" "${GREEN}✓ GRUB updated successfully${RC}"
printf "\n"
printf "%b\n" "${YELLOW}AppArmor boot parameters added:${RC}"
printf "%b\n" "  - apparmor=1"
printf "%b\n" "  - security=apparmor"
printf "\n"
printf "%b\n" "${YELLOW}⚠️  IMPORTANT: Reboot required for changes to take effect${RC}"
printf "%b\n" "${YELLOW}⚠️  Backup saved at: ${BACKUP_FILE}${RC}"
printf "\n"
printf "%b\n" "${GREEN}If you encounter boot issues:${RC}"
printf "%b\n" "1. Boot into recovery mode or live USB"
printf "%b\n" "2. Mount your root partition"
printf "%b\n" "3. Restore backup: cp ${BACKUP_FILE} ${GRUB_CONFIG}"
printf "%b\n" "4. Regenerate GRUB: grub-mkconfig -o /boot/grub/grub.cfg"
