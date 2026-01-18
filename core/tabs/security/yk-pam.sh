#!/bin/sh -e

. "$(dirname "$(realpath "$0")")/../../common-script.sh"

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

# Find available modules
find_modules() {
    for module in sudo su login sshd gdm-password sddm lightdm polkit-1 system-auth system-login common-auth; do
        [ -f "/etc/pam.d/$module" ] && echo "$module"
    done
}

# Configure module
configure_module() {
    MODULE="$1"
    KEY_FILE="$2"
    FILE="/etc/pam.d/$MODULE"
    
    [ ! -f "$FILE" ] && return
    
    "$ESCALATION_TOOL" cp "$FILE" "$FILE.backup-$(date +%Y%m%d-%H%M%S)"
    "$ESCALATION_TOOL" sed -i '/^auth.*pam_u2f\.so/d' "$FILE" 2>/dev/null || true
    
    PAM_LINE="auth sufficient pam_u2f.so authfile=$KEY_FILE cue cue_prompt=Tap_YubiKey"
    
    if grep -q '^#%PAM-1.0' "$FILE"; then
        "$ESCALATION_TOOL" sed -i "/^#%PAM-1.0\$/a $PAM_LINE" "$FILE" 2>/dev/null || true
    elif grep -q '^auth' "$FILE"; then
        "$ESCALATION_TOOL" sed -i "/^auth/i $PAM_LINE" "$FILE" 2>/dev/null || true
    else
        "$ESCALATION_TOOL" sed -i "1i $PAM_LINE" "$FILE" 2>/dev/null || true
    fi
    
    printf "%b\n" "${GREEN}✓ $MODULE${RC}"
}

# Enable daemon
enable_pcscd() {
    "$ESCALATION_TOOL" systemctl enable pcscd 2>/dev/null || true
    "$ESCALATION_TOOL" systemctl start pcscd 2>/dev/null || true
    printf "%b\n" "${GREEN}✓ PC/SC daemon enabled${RC}"
}

# Find backups
find_backups() {
    for f in /etc/pam.d/*.backup-*; do
        [ -f "$f" ] && echo "$f"
    done
}

# Restore backups
restore_backups() {
    printf "%b\n" "${CYAN}=== Restore Backups ===${RC}"
    printf "%b\n"
    
    BACKUPS=$(find_backups)
    [ -z "$BACKUPS" ] && {
        printf "%b\n" "${YELLOW}No backups found${RC}"
        return
    }
    
    i=1
    for b in $BACKUPS; do
        printf "  [$i] $(basename "$b")\n"
        i=$((i + 1))
    done
    printf "%b\n"
    printf "Restore all? (yes/NO): "
    read -r CONFIRM
    
    [ "$CONFIRM" = "yes" ] || return
    
    for b in $BACKUPS; do
        ORIG=$(basename "$b" | sed 's/\.backup-.*//')
        "$ESCALATION_TOOL" cp "$b" "/etc/pam.d/$ORIG"
        printf "%b\n" "${GREEN}✓ Restored $ORIG${RC}"
    done
}

# Main menu
printf "%b\n" "  [1] Configure YubiKey"
printf "%b\n" "  [2] Restore backups"
printf "%b\n" "  [3] Exit"
printf "%b\n"
printf "Select (1-3): "
read -r CHOICE

case "$CHOICE" in
    1)
        printf "%b\n"
        check_pam_u2f
        printf "%b\n"
        KEY=$(setup_yubikey)
        printf "%b\n"
        
        MODULES=$(find_modules)
        [ -z "$MODULES" ] && {
            printf "%b\n" "${RED}No PAM modules found${RC}"
            exit 1
        }
        
        printf "%b\n" "${CYAN}Available modules:${RC}"
        i=1
        for m in $MODULES; do
            printf "  [$i] $m\n"
            i=$((i + 1))
        done
        printf "%b\n"
        printf "Select (space-separated, or 'all'): "
        read -r SEL
        
        [ -z "$SEL" ] && exit 0
        
        SELECTED=""
        if [ "$SEL" = "all" ]; then
            SELECTED="$MODULES"
        else
            for num in $SEL; do
                i=1
                for m in $MODULES; do
                    [ "$i" = "$num" ] && SELECTED="$SELECTED $m"
                    i=$((i + 1))
                done
            done
        fi
        
        printf "%b\n"
        printf "%b\n" "${YELLOW}Will modify: $SELECTED${RC}"
        printf "%b\n" "${RED}WARNING: PAM changes can lock you out!${RC}"
        printf "Continue? (yes/NO): "
        read -r CONF
        
        [ "$CONF" = "yes" ] || exit 0
        
        printf "%b\n"
        printf "%b\n" "${CYAN}Configuring:${RC}"
        for m in $SELECTED; do
            configure_module "$m" "$KEY"
        done
        
        enable_pcscd
        
        printf "%b\n"
        printf "%b\n" "${GREEN}=== Done ===${RC}"
        printf "%b\n" "${YELLOW}Backups: /etc/pam.d/*.backup-*${RC}"
        printf "%b\n" "${CYAN}Testing sudo...${RC}"
        "$ESCALATION_TOOL" -k
        "$ESCALATION_TOOL" echo "✓ Success!"
        ;;
    2)
        printf "%b\n"
        restore_backups
        ;;
    3)
        exit 0
        ;;
    *)
        printf "%b\n" "${RED}Invalid selection${RC}"
        exit 1
        ;;
esac
