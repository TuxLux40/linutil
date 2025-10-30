#!/bin/sh -e

# YubiKey-PAM Configuration
# Adds YubiKey touch-based authentication to sudo via pam_u2f with password fallback.

. ../common-script.sh
checkEnv

SUDO_PAM="/etc/pam.d/sudo"

# Determine the actual user being configured (supports running via sudo)
TARGET_USER=${SUDO_USER:-$USER}
TARGET_HOME=$(eval echo ~"$TARGET_USER")
U2F_DIR="$TARGET_HOME/.config/Yubico"
U2F_KEYS_FILE="$U2F_DIR/u2f_keys"
BACKUP_PATH="$TARGET_HOME/pam_u2f_backup.tgz"

printf "%b\n" "${CYAN}Starting YubiKey PAM setup for user: ${TARGET_USER}${RC}"

# Allow selecting additional PAM targets to enable pam_u2f, beyond sudo
printf "%b\n" "${YELLOW}Wähle, wo pam_u2f aktiviert werden soll (Mehrfachauswahl z. B. 1,4,5).${RC}"
printf "%b\n" "  1) sudo (/etc/pam.d/sudo)"
printf "%b\n" "  2) system-auth (/etc/pam.d/system-auth) [wirkt global]"
printf "%b\n" "  3) login (TTY) (/etc/pam.d/login)"
printf "%b\n" "  4) SDDM (/etc/pam.d/sddm)"
printf "%b\n" "  5) GDM Passwort (/etc/pam.d/gdm-password)"
printf "%b\n" "  6) LightDM (/etc/pam.d/lightdm)"
printf "%b\n" "  7) su (/etc/pam.d/su)"
printf "%b\n" "  8) polkit (/etc/pam.d/polkit-1)"
printf "%b" "Auswahl [Standard: 1]: "
read -r _sel
if [ -z "$_sel" ]; then _sel="1"; fi

# Build target list (always include sudo once)
TARGET_PAM_FILES="$SUDO_PAM"

add_target_if_exists() {
    _file=$1
    _name=$2
    if [ -f "$_file" ]; then
        case " $TARGET_PAM_FILES " in
            *" $_file "*) : ;; # already included
            *) TARGET_PAM_FILES="$TARGET_PAM_FILES $_file" ;;
        esac
    else
        printf "%b\n" "${YELLOW}Überspringe ${_name}: Datei nicht gefunden ($_file).${RC}"
    fi
}

# Parse comma-separated selection
for sel in $(printf "%s" "$_sel" | tr ',' ' '); do
    case "$sel" in
        1) add_target_if_exists "$SUDO_PAM" "sudo" ;;
        2)
            printf "%b" "${YELLOW}Achtung: system-auth beeinflusst viele Dienste. Fortfahren? [y/N] ${RC}"
            read -r _ok
            case "$_ok" in
                y|Y|yes|YES) add_target_if_exists "/etc/pam.d/system-auth" "system-auth" ;;
                *) printf "%b\n" "${YELLOW}system-auth nicht ausgewählt.${RC}" ;;
            esac
            ;;
        3) add_target_if_exists "/etc/pam.d/login" "login" ;;
        4) add_target_if_exists "/etc/pam.d/sddm" "sddm" ;;
        5) add_target_if_exists "/etc/pam.d/gdm-password" "gdm-password" ;;
        6) add_target_if_exists "/etc/pam.d/lightdm" "lightdm" ;;
        7) add_target_if_exists "/etc/pam.d/su" "su" ;;
        8) add_target_if_exists "/etc/pam.d/polkit-1" "polkit-1" ;;
        *) printf "%b\n" "${YELLOW}Unbekannte Auswahl: ${sel} (ignoriert).${RC}" ;;
    esac
done

printf "%b\n" "${CYAN}PAM-Ziele: ${TARGET_PAM_FILES}${RC}"

# Backup selected PAM configuration files (+ optional u2f mappings path if present)
FILES_TO_BACKUP=""
for f in $TARGET_PAM_FILES; do
    case "$f" in
        /etc/pam.d/*) FILES_TO_BACKUP="$FILES_TO_BACKUP ${f#/}" ;;
    esac
done
if "$ESCALATION_TOOL" test -e /etc/u2f_mappings; then
    FILES_TO_BACKUP="$FILES_TO_BACKUP etc/u2f_mappings"
fi
FILES_TO_BACKUP=$(printf "%s" "$FILES_TO_BACKUP" | sed 's/^ *//')
if [ -n "$FILES_TO_BACKUP" ]; then
    "$ESCALATION_TOOL" sh -c "tar -C / -czf '$BACKUP_PATH' $FILES_TO_BACKUP"
    printf "%b\n" "${GREEN}Backup created at ${BACKUP_PATH}${RC}"
else
    printf "%b\n" "${YELLOW}Keine PAM-Dateien zum Sichern gefunden.${RC}"
fi

# Function to ensure pam_u2f line exists in a PAM file in the right position
ensure_pam_u2f_in_file() {
    _pam_file=$1
    NEWLINE='auth sufficient pam_u2f.so cue'
    if "$ESCALATION_TOOL" grep -qsE '^[[:space:]]*auth[[:space:]]+.*pam_u2f\\.so' "$_pam_file"; then
        printf "%b\n" "${CYAN}pam_u2f bereits vorhanden: $_pam_file${RC}"
        return 0
    fi
    printf "%b\n" "${YELLOW}Aktualisiere PAM: $_pam_file${RC}"
    if "$ESCALATION_TOOL" sh -c "awk -v n=\"$NEWLINE\" '
        BEGIN{inserted=0;}
        {
            if (!inserted && \$0 ~ /^[[:space:]]*auth[[:space:]]+(include|substack)[[:space:]]+(common-auth|system-auth)/) {
                print n; print; inserted=1; next
            }
            if (!inserted && \$0 ~ /^[[:space:]]*auth[[:space:]]+/) {
                print n; print; inserted=1; next
            }
            print
        }
        END{
            if (!inserted) print n
        }' '$_pam_file' > '$_pam_file.tmp' && mv '$_pam_file.tmp' '$_pam_file'"; then
        printf "%b\n" "${GREEN}PAM konfiguriert: $_pam_file${RC}"
        return 0
    else
        printf "%b\n" "${RED}Automatisches Einfügen fehlgeschlagen. Fallback: ans Dateiende anhängen.${RC}"
        "$ESCALATION_TOOL" sh -c "printf '%s\n' '$NEWLINE' >> '$_pam_file'"
        printf "%b\n" "${YELLOW}Zeile am Ende von $_pam_file angehängt. Reihenfolge ggf. manuell prüfen.${RC}"
    fi
}

# Apply pam_u2f insertion to all chosen PAM files
for pamf in $TARGET_PAM_FILES; do
    ensure_pam_u2f_in_file "$pamf"
done

# Enroll YubiKey(s) for pam_u2f
printf "%b\n" "${YELLOW}Enrolling YubiKey for pam_u2f…${RC}"

if ! command_exists pamu2fcfg; then
    printf "%b\n" "${RED}pamu2fcfg not found. Install the enrollment tool first:${RC}"
    printf "%b\n" "  - Arch/Manjaro: pam-u2f"
    printf "%b\n" "  - Debian/Ubuntu: libpam-u2f"
    printf "%b\n" "  - Fedora/openSUSE/Void: pam_u2f"
    exit 1
fi

# Create config directory owned by the target user, with secure permissions
"$ESCALATION_TOOL" install -d -m 700 -o "$TARGET_USER" -g "$TARGET_USER" "$U2F_DIR"

# Backup existing keys file if present
if [ -f "$U2F_KEYS_FILE" ]; then
    "$ESCALATION_TOOL" cp -f "$U2F_KEYS_FILE" "$U2F_KEYS_FILE.bak"
    "$ESCALATION_TOOL" chown "$TARGET_USER":"$TARGET_USER" "$U2F_KEYS_FILE.bak" 2>/dev/null || true
    printf "%b\n" "${YELLOW}Existing U2F file backed up: ${U2F_KEYS_FILE}.bak${RC}"
fi

# Helper to run a command as TARGET_USER using available tool (sudo/doas/su)
run_as_target_user() {
    _cmd=$1
    if command_exists sudo; then
        sudo -u "$TARGET_USER" sh -c "$_cmd"
    elif command_exists doas; then
        doas -u "$TARGET_USER" sh -c "$_cmd"
    else
        su - "$TARGET_USER" -c "$_cmd"
    fi
}

printf "%b\n" "${CYAN}Touch your YubiKey when the LED blinks to complete registration…${RC}"
if run_as_target_user "pamu2fcfg | tee '$U2F_KEYS_FILE' >/dev/null"; then
    "$ESCALATION_TOOL" chown "$TARGET_USER":"$TARGET_USER" "$U2F_KEYS_FILE"
    "$ESCALATION_TOOL" chmod 600 "$U2F_KEYS_FILE"
    printf "%b\n" "${GREEN}U2F key mapping created: ${U2F_KEYS_FILE}${RC}"
else
    printf "%b\n" "${RED}Registration failed. Ensure a YubiKey is connected and try again.${RC}"
fi

# Testing and rollback guidance
printf "%b\n" "${YELLOW}Test: open a new terminal, run 'sudo -k; sudo true' and touch your YubiKey when prompted.${RC}"
printf "%b\n" "${YELLOW}Rollback: restore backup with${RC}"
printf "%b\n" "  ${CYAN}$ESCALATION_TOOL tar -C / -xzf '$BACKUP_PATH'${RC}"

printf "%b\n" "${GREEN}YubiKey-PAM setup complete.${RC}"