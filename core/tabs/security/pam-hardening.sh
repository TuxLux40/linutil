#!/bin/sh -e

. ../common-script.sh

DRY_RUN=${DRY_RUN:-0}

if [ "${1:-}" = "--dry-run" ]; then
    DRY_RUN=1
fi

PWQUALITY_FILE="/etc/security/pwquality.conf"
LOGIN_DEFS_FILE="/etc/login.defs"

run_root() {
    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] $*${RC}"
        return 0
    fi

    "$ESCALATION_TOOL" "$@"
}

write_if_changed() {
    source_file=$1
    destination_file=$2

    if [ -f "$destination_file" ] && cmp -s "$source_file" "$destination_file"; then
        printf "%b\n" "${GREEN}$destination_file already matches the hardened baseline${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Writing $destination_file${RC}"

    if [ "$DRY_RUN" = "1" ]; then
        cat "$source_file"
        return 0
    fi

    run_root cp "$source_file" "$destination_file"
}

install_pwquality() {
    printf "%b\n" "${YELLOW}Installing password quality tooling${RC}"

    case "$PACKAGER" in
        pacman)
            run_root "$PACKAGER" -S --needed --noconfirm libpwquality
            ;;
        apt-get|nala)
            run_root "$PACKAGER" install -y libpam-pwquality
            ;;
        dnf)
            run_root "$PACKAGER" install -y libpwquality
            ;;
        zypper)
            run_root "$PACKAGER" install -y pam_pwquality
            ;;
        apk)
            run_root "$PACKAGER" add libpwquality
            ;;
        xbps-install)
            run_root "$PACKAGER" -Sy libpwquality
            ;;
        eopkg)
            run_root "$PACKAGER" install -y libpwquality
            ;;
        *)
            printf "%b\n" "${YELLOW}No known pwquality package mapping for $PACKAGER; continuing with configuration only${RC}"
            ;;
    esac
}

update_login_defs_key() {
    file=$1
    key=$2
    value=$3
    tmp_file=$(mktemp)

    awk -v key="$key" -v value="$value" '
        BEGIN { done = 0 }
        $0 ~ "^[[:space:]]*#?[[:space:]]*" key "([[:space:]]|$)" && !done {
            print key "\t" value
            done = 1
            next
        }
        { print }
        END {
            if (!done) {
                print key "\t" value
            }
        }
    ' "$file" > "$tmp_file"

    mv "$tmp_file" "$file"
}

determine_encrypt_method() {
    case "$DTYPE" in
        alpine)
            printf '%s\n' "SHA512"
            ;;
        *)
            printf '%s\n' "YESCRYPT"
            ;;
    esac
}

apply_login_defs() {
    if [ ! -f "$LOGIN_DEFS_FILE" ]; then
        printf "%b\n" "${YELLOW}$LOGIN_DEFS_FILE not found, skipping login.defs hardening${RC}"
        return 0
    fi

    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' EXIT HUP INT TERM
    cp "$LOGIN_DEFS_FILE" "$tmp_file"

    encrypt_method=$(determine_encrypt_method)
    update_login_defs_key "$tmp_file" "UMASK" "027"
    update_login_defs_key "$tmp_file" "PASS_MAX_DAYS" "365"
    update_login_defs_key "$tmp_file" "PASS_MIN_DAYS" "1"
    update_login_defs_key "$tmp_file" "ENCRYPT_METHOD" "$encrypt_method"

    write_if_changed "$tmp_file" "$LOGIN_DEFS_FILE"
    rm -f "$tmp_file"
    trap - EXIT HUP INT TERM

    printf "%b\n" "${CYAN}PASS_MAX_DAYS and PASS_MIN_DAYS affect new password changes. Existing passwords keep their current aging metadata until changed.${RC}"
}

apply_pwquality() {
    tmp_file=$(mktemp)
    trap 'rm -f "$tmp_file"' EXIT HUP INT TERM

    cat > "$tmp_file" <<'EOF'
# Managed by linutil pam-hardening.sh
minlen = 12
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
EOF

    write_if_changed "$tmp_file" "$PWQUALITY_FILE"
    rm -f "$tmp_file"
    trap - EXIT HUP INT TERM
}

main() {
    checkEnv

    printf "%b\n" "${CYAN}Applying password and PAM hardening defaults...${RC}"
    install_pwquality
    apply_login_defs
    apply_pwquality

    printf "%b\n" "${GREEN}PAM hardening complete.${RC}"
}

main
