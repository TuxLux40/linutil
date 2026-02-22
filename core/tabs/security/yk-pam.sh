#!/bin/sh -e

. ../common-script.sh

TEMP_DIR=""
cleanup() { [ -n "$TEMP_DIR" ] && rm -rf "$TEMP_DIR"; }
trap cleanup EXIT

msg() { printf "%b%s%b\n" "$2" "$1" "$RC"; }
header() { printf "\n%b=== %s ===%b\n\n" "$CYAN" "$1" "$RC"; }
confirm() { printf "%b%s (yes/NO): %b" "$YELLOW" "$1" "$RC"; read -r r; [ "$r" = "yes" ]; }

install_pam_u2f() {
    command_exists pamu2fcfg && return 0
    msg "Installing pam-u2f..." "$CYAN"
    
    case "$PACKAGER" in
        pacman|dnf|zypper|apk) PKG="pam-u2f" ;;
        apt-get|nala) PKG="libpam-u2f"; "$ESCALATION_TOOL" "$PACKAGER" update >/dev/null 2>&1 ;;
        *) msg "Unsupported package manager" "$RED"; return 1 ;;
    esac
    
    "$ESCALATION_TOOL" "$PACKAGER" install -y "$PKG" >/dev/null 2>&1 || { msg "Install failed" "$RED"; return 1; }
    msg "Installed successfully" "$GREEN"
}

check_yubikey() {
    msg "Checking for YubiKey..." "$CYAN"
    timeout 5 "$ESCALATION_TOOL" pamu2fcfg --verbose --no-user-presence 2>&1 | grep -q "Tap_YubiKey\|found 1" || {
        msg "No YubiKey detected" "$RED"
        return 1
    }
    msg "YubiKey detected" "$GREEN"
}

register_yubikey() {
    local user="${1:-${SUDO_USER:-$USER}}"
    local yk_dir="$(eval echo ~$user)/.config/yubico"
    local key_file="$yk_dir/u2f_keys"
    
    mkdir -p "$yk_dir" && chown "$user:$user" "$yk_dir" && chmod 700 "$yk_dir"
    
    if [ -s "$key_file" ]; then
        msg "Existing keys found" "$YELLOW"
        confirm "Overwrite?" || { echo "$key_file"; return 0; }
        cp "$key_file" "${key_file}.backup-$(date +%s)"
    fi
    
    msg "Insert YubiKey and tap it..." "$CYAN"
    TEMP_DIR=$(mktemp -d)
    "$ESCALATION_TOOL" -u "$user" pamu2fcfg -n >"$TEMP_DIR/key" 2>/dev/null || { msg "Registration failed" "$RED"; return 1; }
    "$ESCALATION_TOOL" tee "$key_file" >/dev/null <"$TEMP_DIR/key"
    "$ESCALATION_TOOL" chown "$user:$user" "$key_file" && "$ESCALATION_TOOL" chmod 600 "$key_file"
    msg "Registration successful" "$GREEN"
    echo "$key_file"
}



add_pam_u2f() {
    local file="$1" keyfile="$2" backup="${1}.backup-$(date +%s)"
    
    grep -q '^auth[[:space:]].*pam_u2f\.so' "$file" && { msg "$(basename $file): already configured" "$YELLOW"; return 0; }
    
    "$ESCALATION_TOOL" cp "$file" "$backup"
    
    local tmp=$(mktemp)
    awk -v line="auth sufficient pam_u2f.so authfile=$keyfile cue" '
        !done && /^@include/ { print line; done=1 }
        { print }
        END { if (!done) print line }
    ' "$file" > "$tmp"
    
    "$ESCALATION_TOOL" cp "$tmp" "$file" && rm -f "$tmp"
    msg "$(basename $file): configured" "$GREEN"
}


list_configured() {
    header "Configured Modules"
    local found=0
    for f in /etc/pam.d/*; do
        grep -q '^auth[[:space:]].*pam_u2f\.so' "$f" 2>/dev/null && {
            printf "  %b✓ %s%b\n" "$GREEN" "$(basename $f)" "$RC"
            found=1
        }
    done
    [ "$found" = 0 ] && msg "None configured" "$CYAN"
}

restore_backup() {
    header "Restore from Backup"
    local backups=$(ls /etc/pam.d/*.backup-* 2>/dev/null)
    [ -z "$backups" ] && { msg "No backups found" "$CYAN"; return; }
    
    echo "$backups" | nl -w2 -s'. '
    printf "\nRestore (number or skip): "
    read -r n
    [ -z "$n" ] && return
    
    local backup=$(echo "$backups" | sed -n "${n}p")
    [ -z "$backup" ] && { msg "Invalid selection" "$RED"; return; }
    
    local orig="${backup%.backup-*}"
    "$ESCALATION_TOOL" cp "$backup" "$orig"
    msg "Restored: $(basename $orig)" "$GREEN"
}


configure() {
    header "YubiKey PAM Configuration"
    install_pam_u2f || return 1
    check_yubikey || return 1
    
    local keyfile=$(register_yubikey) || return 1
    
    local modules="sudo su login sshd gdm-password sddm lightdm polkit-1"
    local available=""
    for m in $modules; do
        [ -f "/etc/pam.d/$m" ] && available="$available $m"
    done
    
    [ -z "$available" ] && { msg "No PAM modules found" "$RED"; return 1; }
    
    printf "\nAvailable modules:\n"
    echo "$available" | tr ' ' '\n' | nl -w2 -s'. '
    
    printf "\nSelect (space-separated numbers or 'all'): "
    read -r sel
    [ -z "$sel" ] && return
    
    local selected=""
    [ "$sel" = "all" ] && selected="$available" || {
        for n in $sel; do
            selected="$selected $(echo "$available" | tr ' ' '\n' | sed -n "${n}p")"
        done
    }
    
    [ -z "$selected" ] && { msg "Nothing selected" "$RED"; return 1; }
    
    msg "Will configure: $selected" "$YELLOW"
    msg "WARNING: Keep recovery method ready!" "$YELLOW"
    confirm "Continue?" || return
    
    printf "\n"
    for m in $selected; do
        add_pam_u2f "/etc/pam.d/$m" "$keyfile"
    done
    
    printf "\n"
    msg "Testing sudo..." "$CYAN"
    "$ESCALATION_TOOL" -k && "$ESCALATION_TOOL" echo "Test OK!" >/dev/null 2>&1 && msg "Test passed" "$GREEN" || msg "Test failed" "$RED"
}


main_menu() {
    while true; do
        header "YubiKey PAM Configuration"
        cat << 'EOF'
[1] Configure YubiKey
[2] List configured modules
[3] Restore backup
[4] Exit
EOF
        printf "Select: "
        read -r c
        
        case "$c" in
            1) configure ;;
            2) list_configured ;;
            3) restore_backup ;;
            4) exit 0 ;;
        esac
    done
}

checkEnv
main_menu

