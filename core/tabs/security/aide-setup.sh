#!/bin/sh -e

. ../common-script.sh

DRY_RUN=${DRY_RUN:-0}

installAide() {
    if command_exists aide; then
        printf "%b\n" "${GREEN}AIDE is already installed${RC}"
        return
    fi

    printf "%b\n" "${YELLOW}Installing AIDE...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm aide
            ;;
        apt-get | nala)
            "$ESCALATION_TOOL" "$PACKAGER" update > /dev/null 2>&1
            "$ESCALATION_TOOL" "$PACKAGER" install -y aide
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" install -y aide
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y aide
            ;;
        apk)
            "$ESCALATION_TOOL" "$PACKAGER" add aide
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy aide
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            return 1
            ;;
    esac
    printf "%b\n" "${GREEN}AIDE installed${RC}"
}

verifyAideBinary() {
    if ! command_exists aide; then
        printf "%b\n" "${RED}AIDE binary not found after installation${RC}"
        return 1
    fi

    if ! aide --version > /dev/null 2>&1; then
        printf "%b\n" "${RED}AIDE binary failed to run (possible broken library link)${RC}"
        printf "%b\n" "${YELLOW}Check: ldd \$(command -v aide) | grep 'not found'${RC}"
        return 1
    fi

    printf "%b\n" "${GREEN}AIDE binary OK${RC}"
}

checkConfig() {
    printf "%b\n" "${YELLOW}Checking AIDE configuration...${RC}"

    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would run: aide --config-check${RC}"
        return 0
    fi

    if "$ESCALATION_TOOL" aide --config-check > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}AIDE configuration is valid${RC}"
    else
        printf "%b\n" "${YELLOW}AIDE config check produced warnings (may be non-fatal):${RC}"
        "$ESCALATION_TOOL" aide --config-check 2>&1 || true
    fi
}

detectDbPaths() {
    AIDE_CONF="${AIDE_CONF:-/etc/aide.conf}"

    DB_IN=$("$ESCALATION_TOOL" grep "^database_in" "$AIDE_CONF" 2>/dev/null \
        | sed 's|.*file:||' | head -1)
    DB_OUT=$("$ESCALATION_TOOL" grep "^database_out" "$AIDE_CONF" 2>/dev/null \
        | grep -v "^#" | sed 's|.*file:||' | head -1)

    # Expand @@{DBDIR} if present
    if echo "$DB_IN" | grep -q "@@{DBDIR}"; then
        DBDIR=$("$ESCALATION_TOOL" grep "^@@define DBDIR" "$AIDE_CONF" 2>/dev/null \
            | awk '{print $3}' | head -1)
        DBDIR="${DBDIR:-/var/lib/aide}"
        DB_IN=$(echo "$DB_IN" | sed "s|@@{DBDIR}|$DBDIR|")
        DB_OUT=$(echo "$DB_OUT" | sed "s|@@{DBDIR}|$DBDIR|")
    fi

    DB_IN="${DB_IN:-/var/lib/aide/aide.db.gz}"
    DB_OUT="${DB_OUT:-/var/lib/aide/aide.db.new.gz}"
}

initDatabase() {
    detectDbPaths

    if "$ESCALATION_TOOL" test -f "$DB_IN" 2>/dev/null; then
        printf "%b\n" "${GREEN}AIDE database already exists at $DB_IN${RC}"
        printf "%b\n" "${YELLOW}Skipping initialisation. Run 'sudo aide --init' manually to re-baseline.${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Initialising AIDE database (this may take a few minutes)...${RC}"

    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would run: aide --init && cp $DB_OUT $DB_IN${RC}"
        return 0
    fi

    "$ESCALATION_TOOL" aide --init
    "$ESCALATION_TOOL" cp "$DB_OUT" "$DB_IN"
    printf "%b\n" "${GREEN}AIDE database initialised at $DB_IN${RC}"
}

enableTimer() {
    if ! command_exists systemctl; then
        printf "%b\n" "${YELLOW}systemctl not found, skipping timer setup${RC}"
        return
    fi

    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would enable aidecheck.timer${RC}"
        return 0
    fi

    if systemctl list-unit-files aidecheck.timer > /dev/null 2>&1; then
        "$ESCALATION_TOOL" systemctl enable --now aidecheck.timer
        printf "%b\n" "${GREEN}aidecheck.timer enabled (daily integrity check at 05:00)${RC}"
    else
        printf "%b\n" "${YELLOW}aidecheck.timer unit not found; creating fallback daily cron entry${RC}"
        CRON_LINE="0 5 * * * root $(command -v aide) --check 2>&1 | logger -t aide"
        CRON_FILE="/etc/cron.d/aide-daily"
        if ! "$ESCALATION_TOOL" test -f "$CRON_FILE" 2>/dev/null; then
            printf '%s\n' "$CRON_LINE" | "$ESCALATION_TOOL" tee "$CRON_FILE" > /dev/null
            printf "%b\n" "${GREEN}Cron job written to $CRON_FILE${RC}"
        else
            printf "%b\n" "${GREEN}Cron job already exists at $CRON_FILE${RC}"
        fi
    fi
}

showStatus() {
    detectDbPaths

    printf "%b\n" "${CYAN}AIDE status summary:${RC}"

    if command_exists aide && aide --version > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}  Binary:   OK ($(aide --version 2>&1 | head -1))${RC}"
    else
        printf "%b\n" "${RED}  Binary:   BROKEN${RC}"
    fi

    if "$ESCALATION_TOOL" test -f "$DB_IN" 2>/dev/null; then
        printf "%b\n" "${GREEN}  Database: $DB_IN${RC}"
    else
        printf "%b\n" "${RED}  Database: not found at $DB_IN${RC}"
    fi

    if command_exists systemctl && systemctl list-unit-files aidecheck.timer > /dev/null 2>&1; then
        TIMER_STATE=$(systemctl is-enabled aidecheck.timer 2>/dev/null || echo "disabled")
        printf "%b\n" "${CYAN}  Timer:    aidecheck.timer is $TIMER_STATE${RC}"
    fi
}

main() {
    checkEnv
    printf "%b\n" "${CYAN}Setting up AIDE (Advanced Intrusion Detection Environment)...${RC}"

    installAide
    verifyAideBinary
    checkConfig
    initDatabase
    enableTimer
    showStatus

    printf "%b\n" "${GREEN}AIDE setup complete!${RC}"
    printf "%b\n" "${CYAN}Run 'sudo aide --check' at any time to verify filesystem integrity.${RC}"
    printf "%b\n" "${CYAN}After intentional system changes, re-baseline with: sudo aide --update && sudo cp $DB_OUT $DB_IN${RC}"
}

main
