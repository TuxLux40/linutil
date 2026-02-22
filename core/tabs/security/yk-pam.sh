#!/bin/sh -e

# YubiKey PAM Configuration Script
# Securely configure PAM modules to require YubiKey FIDO2 authentication
# Supports multiple Linux distributions with robust error handling and dry-run mode

. ../common-script.sh

# Global variables
DRY_RUN=0
VERBOSE=1
PAMU2F_PACKAGE=""

# Cleanup function for temp files
cleanup() {
    [ -n "$TEMP_DIR" ] && [ -d "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# ==============================================================================
# LOGGING AND DISPLAY FUNCTIONS
# ==============================================================================

# print_header: Display a formatted section header with color
# Usage: print_header "Section Name"
# Output: Formatted header with cyan color and line breaks
print_header() {
    printf "%b\n" ""
    printf "%b\n" "${CYAN}=== $1 ===${RC}"
    printf "%b\n" ""
}

# log_info: Print informational message
# Usage: log_info "Your message"
log_info() {
    printf "%b\n" "${CYAN}ℹ ${1}${RC}"
}

# log_success: Print success message
# Usage: log_success "Operation completed"
log_success() {
    printf "%b\n" "${GREEN}✓ ${1}${RC}"
}

# log_warn: Print warning message
# Usage: log_warn "Be careful"
log_warn() {
    printf "%b\n" "${YELLOW}⚠ ${1}${RC}"
}

# log_error: Print error message and optionally exit
# Usage: log_error "Something went wrong"
log_error() {
    printf "%b\n" "${RED}✗ ${1}${RC}"
}

# confirm: Ask user for yes/no confirmation
# Usage: confirm "Do you want to continue?" && echo "User said yes"
# Returns: 0 if user confirms, 1 otherwise
confirm() {
    printf "%b" "${YELLOW}${1} (yes/NO): ${RC}"
    read -r response
    [ "$response" = "yes" ]
}

# ==============================================================================
# PAM MODULE INFORMATION
# ==============================================================================

# describe_pam_modules: Display information about PAM modules with safety ratings
# Shows each module's purpose, service type, and safety with u2f configuration
# Usage: describe_pam_modules
describe_pam_modules() {
    print_header "PAM Modules Information"
    
    cat << 'EOF'
SAFE FOR U2F (recommended):
  sudo        - Privilege escalation. Safe: u2f as 2nd auth factor. Fallback works.
  login       - Console login. Safe: Users must have YubiKey. Define fallback clearly.
  sshd        - SSH login. Safe: Can be optional with 'sufficient'. Test remote access first!
  su          - Switch user command. Safe with 'sufficient'. Similar to sudo.

CAUTION (test thoroughly first):
  gdm-password    - GNOME login. May block desktop access if u2f fails. Use 'sufficient'.
  sddm            - KDE/SDDM login. Similar risk. Always use 'sufficient'.
  lightdm         - Light Display Manager. Minimal PAM stack, prefer 'sufficient'.
  polkit-1        - PolicyKit authorization. Could block system dialogs. Test well.

NOT RECOMMENDED:
  system-auth     - Arch master auth file. Affects ALL services! Only if you know implications.
  system-login    - Arch master login file. Similar, affects multiple services.
  common-auth     - Debian/Ubuntu master file. Affects all services via includes!
  common-password - Password changes. Don't use u2f here.

CONTEXT:
  - 'sufficient': YubiKey is optional (fallback to password). Safer against lockout.
  - 'required':   YubiKey is mandatory (both YubiKey AND password). Risk of total lockout!
  - This script uses ONLY 'sufficient' mode for safety.

GENERAL APPROACH:
  1. Start with low-risk modules (sudo, su)
  2. Test thoroughly before adding login/sshd
  3. Keep a recovery method (live USB, recovery account)
  4. Never edit system-auth/common-auth on first try
EOF
}

# ==============================================================================
# UTILITY FUNCTIONS
# ==============================================================================

# get_actual_user: Determine which user is running the script
# When called via sudo/doas, returns the actual user, not root
# Usage: user=$(get_actual_user)
# Output: Username string
get_actual_user() {
    if [ -n "$SUDO_USER" ]; then
        echo "$SUDO_USER"
    else
        echo "$USER"
    fi
}

# check_and_install_pam_u2f: Verify pam-u2f is installed, install if missing
# Detects package manager and installs libpam-u2f / pam-u2f accordingly
# Sets PAMU2F_PACKAGE global variable for reference
check_and_install_pam_u2f() {
    print_header "Checking pam-u2f Installation"
    
    if command_exists pamu2fcfg; then
        log_success "pam-u2f is already installed"
        return 0
    fi
    
    log_warn "pam-u2f not found, attempting installation..."
    
    case "$PACKAGER" in
        pacman)
            PAMU2F_PACKAGE="pam-u2f"
            ;;
        apt-get|nala)
            PAMU2F_PACKAGE="libpam-u2f"
            "$ESCALATION_TOOL" "$PACKAGER" update >/dev/null 2>&1
            ;;
        dnf)
            PAMU2F_PACKAGE="pam-u2f"
            ;;
        zypper)
            PAMU2F_PACKAGE="pam-u2f"
            ;;
        apk)
            PAMU2F_PACKAGE="pam-u2f"
            ;;
        *)
            log_error "Unsupported package manager: $PACKAGER. Please install pam-u2f manually."
            return 1
            ;;
    esac
    
    if [ "$DRY_RUN" = 1 ]; then
        log_info "[DRY RUN] Would install: $PAMU2F_PACKAGE"
        return 0
    fi
    
    log_info "Installing $PAMU2F_PACKAGE via $PACKAGER..."
    if "$ESCALATION_TOOL" "$PACKAGER" install -y "$PAMU2F_PACKAGE" >/dev/null 2>&1; then
        log_success "pam-u2f installed successfully"
        return 0
    else
        log_error "Failed to install pam-u2f. Install manually: sudo $PACKAGER install $PAMU2F_PACKAGE"
        return 1
    fi
}

# check_yubikey_present: Verify a YubiKey is connected by testing pamu2fcfg
# Usage: check_yubikey_present && echo "YubiKey ready"
# Returns: 0 if YubiKey detected, 1 otherwise
check_yubikey_present() {
    log_info "Checking for connected YubiKey..."
    
    # Try with escalation tool first (needed for /dev/hidraw* access)
    if timeout 5 "$ESCALATION_TOOL" pamu2fcfg --verbose --no-user-presence 2>&1 | grep -q "Tap_YubiKey\|found 1"; then
        log_success "YubiKey detected"
        return 0
    else
        log_error "No YubiKey detected or timeout. Please check:"
        log_info "  - YubiKey is inserted properly"
        log_info "  - Run this script with sudo/doas"
        log_info "  - Or add your user to 'plugdev' or 'input' group"
        return 1
    fi
}

# check_existing_u2f_mapping: Check if user already has u2f_keys registered
# Returns 0 if mapping exists, 1 if new registration needed
# Warns user before overwriting existing keys
check_existing_u2f_mapping() {
    local user="$1"
    local keyfile="${2:-$3}"
    
    if [ -f "$keyfile" ] && [ -s "$keyfile" ]; then
        log_warn "Existing u2f_keys found for $user:"
        log_info "File: $keyfile"
        log_info "Entries:"
        sed 's/:.*/:***REDACTED***/g' "$keyfile" | sed 's/^/  /'
        
        if ! confirm "Overwrite existing keys?"; then
            log_info "Keeping existing keys"
            return 0
        fi
        
        log_warn "Backing up existing keys..."
        if [ "$DRY_RUN" = 0 ]; then
            cp "$keyfile" "${keyfile}.backup-$(date +%s)"
        fi
        return 1  # Signal that we should re-register
    fi
    return 1  # No existing mapping
}

# setup_yubikey_registration: Register YubiKey credentials for a user
# Interactive: prompts user to insert YubiKey and tap
# Stores mapping in ~/.config/yubico/u2f_keys
# Returns path to key file on success
setup_yubikey_registration() {
    local user="$1"
    local user_home
    local yk_dir
    local key_file
    
    user_home=$(eval echo "~$user")
    yk_dir="$user_home/.config/yubico"
    key_file="$yk_dir/u2f_keys"
    
    print_header "YubiKey Registration for $user"
    
    log_info "Creating .config/yubico directory..."
    if [ "$DRY_RUN" = 0 ]; then
        mkdir -p "$yk_dir"
        chown "$user:$user" "$yk_dir"
        chmod 700 "$yk_dir"
    fi
    
    # Check for existing mapping
    if [ -f "$key_file" ] && [ -s "$key_file" ]; then
        check_existing_u2f_mapping "$user" "$key_file"
        if [ $? -eq 0 ]; then
            echo "$key_file"
            return 0
        fi
    fi
    
    log_info "Please insert YubiKey and get ready to tap it..."
    log_warn "You will have 30 seconds to respond"
    printf "\n"
    
    if [ "$DRY_RUN" = 1 ]; then
        echo "$key_file"
        return 0
    fi
    
    # Create temporary file for key registration
    TEMP_DIR=$(mktemp -d)
    temp_key="$TEMP_DIR/temp_key"
    
    if ! "$ESCALATION_TOOL" -u "$user" pamu2fcfg -n >"$temp_key" 2>/dev/null; then
        log_error "YubiKey registration failed. Please check:"
        log_info "  - YubiKey is inserted"
        log_info "  - You tapped the YubiKey"
        log_info "  - pam-u2f is correctly installed"
        return 1
    fi
    
    # Validate that we got a key
    if [ ! -s "$temp_key" ]; then
        log_error "No key data received from pamu2fcfg"
        return 1
    fi
    
    # Write to actual location
    if [ "$DRY_RUN" = 0 ]; then
        "$ESCALATION_TOOL" tee "$key_file" >/dev/null < "$temp_key"
        "$ESCALATION_TOOL" chown "$user:$user" "$key_file"
        "$ESCALATION_TOOL" chmod 600 "$key_file"
    fi
    
    log_success "YubiKey registered successfully"
    echo "$key_file"
}

# ==============================================================================
# PAM FILE MANIPULATION
# ==============================================================================

# backup_pam_file: Create timestamped backup of PAM config file
# Usage: backup_pam_file "/etc/pam.d/sudo"
# Creates file.backup-TIMESTAMP
backup_pam_file() {
    local file="$1"
    local backup="${file}.backup-$(date +%s)"
    
    if [ "$DRY_RUN" = 0 ]; then
        "$ESCALATION_TOOL" cp "$file" "$backup"
        log_info "Backup created: $backup"
    else
        log_info "[DRY RUN] Would create backup: $backup"
    fi
}

# check_pam_line_exists: Check if u2f auth line already exists in file
# Returns 0 if line exists, 1 if not
check_pam_line_exists() {
    local file="$1"
    
    grep -q '^auth[[:space:]].*pam_u2f\.so' "$file"
}

# add_u2f_auth_line: Safely add u2f auth line to PAM file
# Inserts before any @include directives or at appropriate position
# Usage: add_u2f_auth_line "/etc/pam.d/sudo" "/home/user/.config/yubico/u2f_keys"
add_u2f_auth_line() {
    local file="$1"
    local keyfile="$2"
    local pam_line="auth sufficient pam_u2f.so authfile=$keyfile cue"
    local temp_file
    local insert_done=0
    
    # Check if line already exists
    if check_pam_line_exists "$file"; then
        log_warn "$(basename "$file"): u2f line already exists, skipping"
        return 0
    fi
    
    if [ "$DRY_RUN" = 1 ]; then
        log_info "[DRY RUN] Would add u2f line to: $(basename "$file")"
        return 0
    fi
    
    temp_file=$(mktemp)
    
    # Process line by line, inserting at appropriate spot
    while IFS= read -r line; do
        # Insert before @include common-auth (Debian/Ubuntu pattern)
        if [ "$insert_done" = 0 ] && echo "$line" | grep -q '^@include'; then
            echo "$pam_line" >> "$temp_file"
            insert_done=1
        fi
        
        echo "$line" >> "$temp_file"
    done < "$file"
    
    # If we didn't insert yet, add at the beginning (preserve header if exists)
    if [ "$insert_done" = 0 ]; then
        {
            # Check for PAM header and preserve it
            if head -1 "$file" | grep -q '^#%PAM'; then
                head -1 "$file"
                echo "$pam_line"
                tail -n +2 "$file"
            else
                echo "$pam_line"
                cat "$file"
            fi
        } > "$temp_file"
    fi
    
    # Validate that line was added
    if ! grep -q "^auth[[:space:]].*pam_u2f\.so" "$temp_file"; then
        log_error "Failed to add u2f line to temp file"
        rm -f "$temp_file"
        return 1
    fi
    
    # Replace original file
    "$ESCALATION_TOOL" cp "$temp_file" "$file"
    rm -f "$temp_file"
    
    log_success "$(basename "$file"): u2f auth line added"
    return 0
}

# ==============================================================================
# LISTING AND DISCOVERY FUNCTIONS
# ==============================================================================

# find_pam_files: Discover all available PAM configuration files
# Filters out system/common auth files, shows user-selectable modules
# Usage: find_pam_files
# Output: Space-separated list of module names
find_pam_files() {
    # Standard modules safe to configure individually
    local modules="sudo su login sshd gdm-password sddm lightdm polkit-1"
    local available ""
    
    for module in $modules; do
        if [ -f "/etc/pam.d/$module" ]; then
            available="$available $module"
        fi
    done
    
    echo "$available" | sed 's/^ //'
}

# list_configured_modules: Show PAM modules that already have u2f configured
# Usage: list_configured_modules
list_configured_modules() {
    print_header "Currently Configured Modules"
    
    local found=0
    
    for file in /etc/pam.d/*; do
        if grep -q '^auth[[:space:]].*pam_u2f\.so' "$file" 2>/dev/null; then
            local module=$(basename "$file")
            printf "  %b✓ %s%b\n" "$GREEN" "$module" "$RC"
            found=1
        fi
    done
    
    if [ "$found" = 0 ]; then
        log_info "No u2f-configured modules found"
    fi
}

# find_backup_files: Locate all PAM backup files
# Usage: find_backup_files
# Output: Space-separated list of backup file paths
find_backup_files() {
    local backups=""
    
    for f in /etc/pam.d/*.backup-*; do
        [ -f "$f" ] && backups="$backups $f"
    done
    
    echo "$backups" | sed 's/^ //'
}

# ==============================================================================
# RESTORE FUNCTIONALITY
# ==============================================================================

# restore_from_backup: Interactive restore from backup files
# Lists available backups and prompts user to restore specific ones
restore_from_backup() {
    print_header "Restore from Backup"
    
    local backups
    backups=$(find_backup_files)
    
    if [ -z "$backups" ]; then
        log_info "No backup files found"
        return 0
    fi
    
    log_info "Available backups:"
    printf "\n"
    
    local i=1
    for backup in $backups; do
        printf "  [%d] %s\n" "$i" "$(basename "$backup")"
        i=$((i + 1))
    done
    
    printf "\n"
    printf "Select backup to restore (number or 'all'), or press Enter to skip: "
    read -r selection
    
    [ -z "$selection" ] && return 0
    
    if [ "$selection" = "all" ]; then
        log_warn "This will overwrite ALL current PAM files with their backups"
        if ! confirm "Continue with full restore?"; then
            log_info "Restore cancelled"
            return 0
        fi
        
        for backup in $backups; do
            local original="${backup%.backup-*}"
            if [ "$DRY_RUN" = 0 ]; then
                "$ESCALATION_TOOL" cp "$backup" "$original"
                log_success "Restored: $(basename "$original")"
            else
                log_info "[DRY RUN] Would restore: $(basename "$original")"
            fi
        done
    else
        # Restore specific backup by number
        local i=1
        for backup in $backups; do
            if [ "$i" = "$selection" ]; then
                local original="${backup%.backup-*}"
                if [ "$DRY_RUN" = 0 ]; then
                    "$ESCALATION_TOOL" cp "$backup" "$original"
                    log_success "Restored: $(basename "$original")"
                else
                    log_info "[DRY RUN] Would restore: $(basename "$original")"
                fi
                return 0
            fi
            i=$((i + 1))
        done
        
        log_error "Invalid selection"
    fi
}

# ==============================================================================
# MAIN CONFIGURATION WORKFLOW
# ==============================================================================

# configure_modules: Main workflow for YubiKey PAM configuration
# Handles module selection, configuration, and testing
configure_modules() {
    print_header "YubiKey PAM Configuration"
    
    # Step 1: Check and install pam-u2f
    if ! check_and_install_pam_u2f; then
        return 1
    fi
    
    printf "\n"
    
    # Step 2: Check for YubiKey
    if ! check_yubikey_present; then
        return 1
    fi
    
    printf "\n"
    
    # Step 3: Register YubiKey
    local actual_user
    local keyfile
    
    actual_user=$(get_actual_user)
    keyfile=$(setup_yubikey_registration "$actual_user") || return 1
    
    printf "\n"
    
    # Step 4: Module selection
    log_info "Finding available PAM modules..."
    local modules
    modules=$(find_pam_files)
    
    if [ -z "$modules" ]; then
        log_error "No PAM modules found on this system"
        return 1
    fi
    
    print_header "Available PAM Modules"
    local i=1
    for m in $modules; do
        printf "  [%d] %s\n" "$i" "$m"
        i=$((i + 1))
    done
    
    printf "\n"
    printf "Select modules to configure (space-separated numbers, 'all', or skip): "
    read -r selection
    
    [ -z "$selection" ] && {
        log_info "Configuration cancelled"
        return 0
    }
    
    # Parse selection
    local selected=""
    if [ "$selection" = "all" ]; then
        selected="$modules"
    else
        for num in $selection; do
            local i=1
            for m in $modules; do
                if [ "$i" = "$num" ]; then
                    selected="$selected $m"
                fi
                i=$((i + 1))
            done
        done
    fi
    
    if [ -z "$selected" ]; then
        log_error "No valid modules selected"
        return 1
    fi
    
    # Step 5: Confirmation
    printf "\n"
    log_warn "Will configure the following modules:"
    printf "  "
    printf "%b%s%b " "$GREEN" "$selected" "$RC"
    printf "\n\n"
    
    log_warn "WARNING: Incorrect PAM configuration can lock you out of your system!"
    printf "\n"
    log_info "Recommendations:"
    log_info "  • Keep a recovery method (live USB, separate admin account)"
    log_info "  • Test with sudo first before login/sshd"
    log_info "  • Be ready to use recovery (backups are at /etc/pam.d/*.backup-*)"
    printf "\n"
    
    if ! confirm "Continue with configuration?"; then
        log_info "Configuration cancelled"
        return 0
    fi
    
    # Step 6: Apply configuration
    printf "\n"
    print_header "Applying Configuration"
    
    local failed=0
    for module in $selected; do
        local file="/etc/pam.d/$module"
        
        if [ ! -f "$file" ]; then
            log_error "Module file not found: $file"
            failed=$((failed + 1))
            continue
        fi
        
        # Create backup
        backup_pam_file "$file"
        
        # Add u2f line
        if ! add_u2f_auth_line "$file" "$keyfile"; then
            failed=$((failed + 1))
        fi
    done
    
    printf "\n"
    if [ "$failed" = 0 ]; then
        print_header "Configuration Complete"
        log_success "All modules configured successfully"
        
        if [ "$DRY_RUN" = 0 ]; then
            log_info "Backups saved to: /etc/pam.d/*.backup-*"
            printf "\n"
            log_info "Testing with sudo (clear cache first)..."
            
            if "$ESCALATION_TOOL" -k; then
                if "$ESCALATION_TOOL" echo "✓ Success! PAM is working correctly" >/dev/null 2>&1; then
                    log_success "PAM test successful"
                else
                    log_error "PAM test failed"
                fi
            else
                log_error "Could not clear sudo cache"
            fi
        fi
    else
        log_error "$failed module(s) failed to configure. Check backups to restore."
    fi
}

# ==============================================================================
# MAIN MENU
# ==============================================================================

main_menu() {
    while true; do
        printf "\n"
        print_header "YubiKey PAM Configuration"
        
        cat << 'EOF'
[1] Configure YubiKey for PAM modules
[2] List currently configured modules
[3] Show PAM module information
[4] Manage backups (view/restore)
[5] Exit

EOF
        
        printf "Select an option (1-5): "
        read -r choice
        
        case "$choice" in
            1)
                configure_modules
                ;;
            2)
                printf "\n"
                list_configured_modules
                ;;
            3)
                describe_pam_modules
                ;;
            4)
                printf "\n"
                restore_from_backup
                ;;
            5)
                log_info "Goodbye"
                exit 0
                ;;
            *)
                log_error "Invalid selection. Please choose 1-5."
                ;;
        esac
    done
}

# ==============================================================================
# SCRIPT INITIALIZATION
# ==============================================================================

# Parse command-line arguments
for arg in "$@"; do
    case "$arg" in
        --dry-run)
            DRY_RUN=1
            log_warn "DRY RUN MODE ENABLED - No changes will be made"
            ;;
        --verbose)
            VERBOSE=1
            ;;
        *)
            printf "%b\n" "${YELLOW}Unknown option: $arg${RC}"
            ;;
    esac
done

# Check environment and permissions
checkEnv

# Start main menu
main_menu
