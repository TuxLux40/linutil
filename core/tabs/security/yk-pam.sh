#!/bin/sh -e

. "$(dirname "$(realpath "$0")")/../common-script.sh"

checkEnv

#############################
# YubiKey-PAM Configuration
#############################

printf "%b\n" "${CYAN}=== YubiKey PAM Configuration ===${RC}"
printf "%b\n"

# Check if pam-u2f is installed
check_pam_u2f() {
    if ! command -v pamu2fcfg >/dev/null 2>&1; then
        printf "%b\n" "${RED}Installing pam-u2f...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm pam-u2f 2>&1 | head -5
                ;;
            apt-get|nala)
                "$ESCALATION_TOOL" "$PACKAGER" update >/dev/null 2>&1
                "$ESCALATION_TOOL" "$PACKAGER" install -y libpam-u2f 2>&1 | head -5
                ;;
            dnf)
                "$ESCALATION_TOOL" "$PACKAGER" install -y pam-u2f 2>&1 | head -5
                ;;
            zypper)
                "$ESCALATION_TOOL" "$PACKAGER" install -y pam-u2f 2>&1 | head -5
                ;;
            *)
                printf "%b\n" "${RED}Please install pam-u2f manually${RC}"
                exit 1
                ;;
        esac
        printf "%b\n" "${GREEN}pam-u2f installed${RC}"
    else
        printf "%b\n" "${GREEN}pam-u2f already installed${RC}"
    fi
}

# Get actual user
# This function makes sure that 'sudo ./yk-pam.sh' puts the config in the right user's home, not root's.
get_actual_user() {
    if [ -n "$SUDO_USER" ]; then
        echo "$SUDO_USER"
    else
        echo "$USER"
    fi
}

# Setup YubiKey
setup_yubikey() {
    ACTUAL_USER=$(get_actual_user)
    USER_HOME=$(eval echo "~$ACTUAL_USER")
    YK_DIR="$USER_HOME/.config/yubico"
    KEY_FILE="$YK_DIR/u2f_keys"
    
    printf "%b\n" "${CYAN}Setting up YubiKey for: $ACTUAL_USER${RC}"
    
    mkdir -p "$YK_DIR"
    chown -R "$ACTUAL_USER:$ACTUAL_USER" "$YK_DIR"
    
    if [ -s "$KEY_FILE" ]; then
        printf "%b\n" "${YELLOW}YubiKey already registered${RC}"
    else
        printf "%b\n" "${YELLOW}Insert YubiKey and tap...${RC}"
        "$ESCALATION_TOOL" -u "$ACTUAL_USER" pamu2fcfg > "$KEY_FILE" 2>/dev/null
        chown "$ACTUAL_USER:$ACTUAL_USER" "$KEY_FILE"
        chmod 600 "$KEY_FILE"
        printf "%b\n" "${GREEN}YubiKey registered${RC}"
    fi
    
    echo "$KEY_FILE"
}

# PAM helpers
backup_file() {
    FILE="$1"
    [ -f "$FILE" ] || return
    "$ESCALATION_TOOL" cp "$FILE" "$FILE.backup-$(date +%Y%m%d-%H%M%S)"
}

insert_u2f_auth_line() {
    FILE="$1"
    KEY_FILE="$2"
    PAM_LINE="auth sufficient pam_u2f.so authfile=$KEY_FILE cue cue_prompt=Tap_YubiKey"

    "$ESCALATION_TOOL" sed -i '/^auth.*pam_u2f\.so/d' "$FILE" 2>/dev/null || true

    if grep -q '^#%PAM-1.0' "$FILE"; then
        "$ESCALATION_TOOL" sed -i "/^#%PAM-1.0\$/a $PAM_LINE" "$FILE" 2>/dev/null || true
    elif grep -q '^auth' "$FILE"; then
        "$ESCALATION_TOOL" sed -i "/^auth/i $PAM_LINE" "$FILE" 2>/dev/null || true
    else
        "$ESCALATION_TOOL" sed -i "1i $PAM_LINE" "$FILE" 2>/dev/null || true
    fi
}

ensure_sudo_u2f() {
    FILE="/etc/pam.d/sudo"
    [ -f "$FILE" ] || return
    backup_file "$FILE"
    insert_u2f_auth_line "$FILE" "$1"
    printf "%b\n" "${GREEN}✓ sudo${RC}"
}

ensure_polkit_u2f() {
    KEY_FILE="$1"
    FILE="/etc/pam.d/polkit-1"

    if [ ! -f "$FILE" ]; then
        if [ -f "/usr/lib/pam.d/polkit-1" ]; then
            "$ESCALATION_TOOL" cp "/usr/lib/pam.d/polkit-1" "$FILE"
        elif [ -f "/usr/lib64/pam.d/polkit-1" ]; then
            "$ESCALATION_TOOL" cp "/usr/lib64/pam.d/polkit-1" "$FILE"
        else
            printf "%b\n" "${RED}polkit-1 PAM profile not found${RC}"
            return
        fi
        "$ESCALATION_TOOL" sed -i '1a # Managed by linutil yk-pam.sh' "$FILE"
    else
        backup_file "$FILE"
    fi

    insert_u2f_auth_line "$FILE" "$KEY_FILE"
    printf "%b\n" "${GREEN}✓ polkit-1${RC}"
}

remove_u2f_from_file() {
    FILE="$1"
    [ -f "$FILE" ] || return
    backup_file "$FILE"
    "$ESCALATION_TOOL" sed -i '/^auth.*pam_u2f\.so/d' "$FILE" 2>/dev/null || true
}

restore_default_profile() {
    remove_u2f_from_file "/etc/pam.d/sudo"

    if [ -f "/etc/pam.d/polkit-1" ]; then
        if grep -q '^# Managed by linutil yk-pam.sh' "/etc/pam.d/polkit-1"; then
            "$ESCALATION_TOOL" rm -f "/etc/pam.d/polkit-1"
        else
            remove_u2f_from_file "/etc/pam.d/polkit-1"
        fi
    fi
}

describe_pam_targets() {
    printf "%b\n" "${CYAN}PAM target files:${RC}"
    printf "%b\n" "  /etc/pam.d/sudo        - sudo authentication (CLI privilege escalation)"
    printf "%b\n" "  /etc/pam.d/polkit-1    - polkit auth dialogs (GUI privilege prompts)"
    printf "%b\n" "  /etc/pam.d/system-auth - common auth stack (used by many services) [advanced]"
    printf "%b\n" "  /etc/pam.d/system-login- common login stack (getty/display managers) [advanced]"
    printf "%b\n" "  /etc/pam.d/sddm        - display manager login"
    printf "%b\n" "${YELLOW}This script only touches sudo and polkit-1.${RC}"
    printf "%b\n"
}

# Enable daemon
enable_pcscd() {
    "$ESCALATION_TOOL" systemctl enable pcscd 2>/dev/null || true
    "$ESCALATION_TOOL" systemctl start pcscd 2>/dev/null || true
    printf "%b\n" "${GREEN}✓ PC/SC daemon enabled${RC}"
}

# Main menu
describe_pam_targets

printf "%b\n" "  [1] Profile: Default (no YubiKey/U2F)"
printf "%b\n" "  [2] Profile: Sudo only"
printf "%b\n" "  [3] Profile: Sudo + Polkit"
printf "%b\n" "  [4] Exit"
printf "%b\n"
printf "Select (1-4): "
read -r CHOICE

case "$CHOICE" in
    1)
        printf "%b\n"
        printf "%b\n" "${YELLOW}Restoring default (no YubiKey)...${RC}"
        restore_default_profile
        printf "%b\n" "${GREEN}Done.${RC}"
        ;;
    2)
        printf "%b\n"
        check_pam_u2f
        printf "%b\n"
        KEY=$(setup_yubikey)
        printf "%b\n"
        printf "%b\n" "${YELLOW}Will modify: sudo${RC}"
        printf "%b\n" "${RED}WARNING: PAM changes can lock you out!${RC}"
        printf "Continue? (yes/NO): "
        read -r CONF
        [ "$CONF" = "yes" ] || exit 0
        printf "%b\n"
        ensure_sudo_u2f "$KEY"
        enable_pcscd
        printf "%b\n" "${GREEN}=== Done ===${RC}"
        ;;
    3)
        printf "%b\n"
        check_pam_u2f
        printf "%b\n"
        KEY=$(setup_yubikey)
        printf "%b\n"
        printf "%b\n" "${YELLOW}Will modify: sudo, polkit-1${RC}"
        printf "%b\n" "${RED}WARNING: PAM changes can lock you out!${RC}"
        printf "Continue? (yes/NO): "
        read -r CONF
        [ "$CONF" = "yes" ] || exit 0
        printf "%b\n"
        ensure_sudo_u2f "$KEY"
        ensure_polkit_u2f "$KEY"
        enable_pcscd
        printf "%b\n" "${GREEN}=== Done ===${RC}"
        ;;
    4)
        exit 0
        ;;
    *)
        printf "%b\n" "${RED}Invalid selection${RC}"
        exit 1
        ;;
esac
