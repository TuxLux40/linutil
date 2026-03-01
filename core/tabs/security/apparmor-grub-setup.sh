#!/bin/sh -e

. ../common-script.sh

GRUB_CONFIG="/etc/default/grub"
BACKUP_FILE=""
TEMP_CONFIG=""
GRUB_UPDATED=false

cleanup() {
    rm -f "$TEMP_CONFIG"
    # If something failed after the backup was taken but before GRUB was fully updated,
    # restore the original config automatically.
    if [ "$GRUB_UPDATED" = "false" ] && [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ]; then
        printf "%b\n" "${YELLOW}Unexpected exit — restoring GRUB config from backup...${RC}"
        cp "$BACKUP_FILE" "$GRUB_CONFIG" && printf "%b\n" "${GREEN}✓ Backup restored${RC}"
    fi
}
trap cleanup EXIT

# --- Pre-flight checks (before prompting the user) ---

if [ "$(id -u)" -ne 0 ]; then
    printf "%b\n" "${RED}Error: This script must be run as root (use sudo)${RC}"
    exit 1
fi

if [ ! -f "$GRUB_CONFIG" ]; then
    printf "%b\n" "${RED}Error: $GRUB_CONFIG not found. Is GRUB installed?${RC}"
    exit 1
fi

if ! command -v apparmor_parser > /dev/null 2>&1; then
    printf "%b\n" "${RED}Error: AppArmor is not installed. Install the 'apparmor' package first.${RC}"
    exit 1
fi

# --- Idempotency check (before prompting or making any changes) ---

if grep -q 'apparmor=1' "$GRUB_CONFIG" && grep -q 'security=apparmor' "$GRUB_CONFIG"; then
    printf "%b\n" "${GREEN}✓ AppArmor boot parameters already configured. Nothing to do.${RC}"
    exit 0
fi

# --- Warning and confirmation ---

printf "%b\n" "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
printf "%b\n" "${RED}  WARNING: MODIFYING GRUB BOOT PARAMETERS${RC}"
printf "%b\n" "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
printf "%b\n" "${YELLOW}This script will add AppArmor parameters to GRUB.${RC}"
printf "%b\n" "${YELLOW}If something goes wrong your system may not boot.${RC}"
printf "%b\n" "${YELLOW}Be especially careful with custom GRUB configs or encrypted disks.${RC}"
printf "\n"
printf "%b\n" "${YELLOW}Before continuing, ensure you have:${RC}"
printf "%b\n" "  1. A full system backup"
printf "%b\n" "  2. A live USB or recovery media"
printf "%b\n" "  3. The ability to restore from backup"
printf "\n"
printf "%b" "Type 'I UNDERSTAND THE RISKS' to continue: "
read -r confirmation

if [ "$confirmation" != "I UNDERSTAND THE RISKS" ]; then
    printf "%b\n" "${RED}Aborted.${RC}"
    exit 1
fi
printf "\n"

# --- Backup ---

BACKUP_FILE="${GRUB_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
printf "%b\n" "${YELLOW}Creating backup: ${BACKUP_FILE}${RC}"
cp "$GRUB_CONFIG" "$BACKUP_FILE"

# --- Build updated GRUB_CMDLINE_LINUX_DEFAULT ---

if ! grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_CONFIG"; then
    printf "%b\n" "${RED}Error: GRUB_CMDLINE_LINUX_DEFAULT not found in $GRUB_CONFIG${RC}"
    exit 1
fi

# cut -d'"' -f2 correctly returns empty string when the value is ""
CURRENT_CMDLINE=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$GRUB_CONFIG" | head -n 1 | cut -d'"' -f2)

NEW_CMDLINE="$CURRENT_CMDLINE"

if ! printf '%s ' "$NEW_CMDLINE" | grep -q 'apparmor=1'; then
    NEW_CMDLINE="${NEW_CMDLINE} apparmor=1"
fi

if ! printf '%s ' "$NEW_CMDLINE" | grep -q 'security=apparmor'; then
    NEW_CMDLINE="${NEW_CMDLINE} security=apparmor"
fi

# Strip any leading whitespace (happens when CURRENT_CMDLINE was empty)
NEW_CMDLINE=$(printf '%s' "$NEW_CMDLINE" | sed 's/^[[:space:]]*//')

printf "%b\n" "${YELLOW}Current cmdline:${RC} $CURRENT_CMDLINE"
printf "%b\n" "${YELLOW}New cmdline:    ${RC} $NEW_CMDLINE"

# --- Write updated config via temp file ---

TEMP_CONFIG=$(mktemp)

# Use a control character (ASCII 001) as the sed delimiter to avoid clashing
# with any character that could legitimately appear in a kernel cmdline.
sed "s$(printf '\001')^GRUB_CMDLINE_LINUX_DEFAULT=.*$(printf '\001')GRUB_CMDLINE_LINUX_DEFAULT=\"$NEW_CMDLINE\"$(printf '\001')" \
    "$GRUB_CONFIG" > "$TEMP_CONFIG"

if ! grep -q 'apparmor=1' "$TEMP_CONFIG" || ! grep -q 'security=apparmor' "$TEMP_CONFIG"; then
    printf "%b\n" "${RED}ERROR: sed substitution did not produce expected output${RC}"
    exit 1
fi

cp "$TEMP_CONFIG" "$GRUB_CONFIG"

if ! grep -q 'apparmor=1' "$GRUB_CONFIG" || ! grep -q 'security=apparmor' "$GRUB_CONFIG"; then
    printf "%b\n" "${RED}ERROR: Verification failed after writing config${RC}"
    exit 1
fi

printf "%b\n" "${GREEN}✓ GRUB config updated${RC}"

# --- Regenerate GRUB ---

printf "%b\n" "${YELLOW}Updating GRUB bootloader...${RC}"

# Detect the generated grub.cfg path (for distros without update-grub)
GRUB_CFG=""
for path in /boot/grub/grub.cfg /boot/grub2/grub.cfg; do
    if [ -f "$path" ]; then
        GRUB_CFG="$path"
        break
    fi
done

if command -v update-grub > /dev/null 2>&1; then
    update-grub
elif command -v grub-mkconfig > /dev/null 2>&1 && [ -n "$GRUB_CFG" ]; then
    grub-mkconfig -o "$GRUB_CFG"
elif command -v grub2-mkconfig > /dev/null 2>&1 && [ -n "$GRUB_CFG" ]; then
    grub2-mkconfig -o "$GRUB_CFG"
else
    printf "%b\n" "${RED}ERROR: Cannot find a GRUB update command (update-grub / grub-mkconfig / grub2-mkconfig).${RC}"
    printf "%b\n" "${YELLOW}GRUB_CMDLINE_LINUX_DEFAULT has been updated in $GRUB_CONFIG but the bootloader was not regenerated.${RC}"
    printf "%b\n" "${YELLOW}Run the appropriate command manually, or restore the backup: ${BACKUP_FILE}${RC}"
    exit 1
fi

GRUB_UPDATED=true
printf "%b\n" "${GREEN}✓ GRUB updated successfully${RC}"
printf "\n"
printf "%b\n" "${YELLOW}AppArmor parameters added to boot:${RC}"
printf "%b\n" "  - apparmor=1"
printf "%b\n" "  - security=apparmor"
printf "\n"
printf "%b\n" "${YELLOW}IMPORTANT: Reboot required for changes to take effect.${RC}"
printf "%b\n" "${YELLOW}Backup saved at: ${BACKUP_FILE}${RC}"
printf "\n"
printf "%b\n" "${GREEN}If you encounter boot issues after rebooting:${RC}"
printf "%b\n" "  1. Boot into recovery mode or a live USB"
printf "%b\n" "  2. Mount your root partition"
printf "%b\n" "  3. Restore: cp ${BACKUP_FILE} ${GRUB_CONFIG}"
printf "%b\n" "  4. Regenerate: grub-mkconfig -o ${GRUB_CFG:-/boot/grub/grub.cfg}"
