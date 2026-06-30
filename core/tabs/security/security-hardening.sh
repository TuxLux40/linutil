#!/bin/sh -e

. ../common-script.sh

# ─── Global options ───────────────────────────────────────────────────────────

DRY_RUN=${DRY_RUN:-0}
HARDENING_PROFILE=${HARDENING_PROFILE:-desktop}
PROC_HARDENING_HIDEPID=${PROC_HARDENING_HIDEPID:-ask}
RUN_ALL=0
REQUESTED_MODULES=""

parse_args() {
    for arg in "$@"; do
        case "$arg" in
            --dry-run)      DRY_RUN=1 ;;
            --all)          RUN_ALL=1 ;;
            --profile=*)    HARDENING_PROFILE="${arg#*=}" ;;
            --hidepid)      PROC_HARDENING_HIDEPID=1 ;;
            --no-hidepid)   PROC_HARDENING_HIDEPID=0 ;;
            -*)             printf "%b\n" "${RED}Unknown option: $arg${RC}"; exit 1 ;;
            *)              REQUESTED_MODULES="$REQUESTED_MODULES $arg" ;;
        esac
    done
}

# ─── Shared helpers ───────────────────────────────────────────────────────────

run_root() {
    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] $*${RC}"
        return 0
    fi
    "$ESCALATION_TOOL" "$@"
}

write_if_changed() {
    src=$1; dst=$2
    if [ -f "$dst" ] && cmp -s "$src" "$dst"; then
        printf "%b\n" "${GREEN}$dst already matches the hardened baseline${RC}"
        return 0
    fi
    printf "%b\n" "${YELLOW}Writing $dst${RC}"
    if [ "$DRY_RUN" = "1" ]; then
        cat "$src"
        return 0
    fi
    run_root mkdir -p "$(dirname "$dst")"
    run_root cp "$src" "$dst"
}

# Update a key in a config file; handles commented-out and missing lines.
update_config_key() {
    file=$1; key=$2; value=$3; sep=${4:- }
    tmp=$(mktemp)
    awk -v key="$key" -v value="$value" -v sep="$sep" '
        BEGIN { done=0 }
        $0 ~ "^[[:space:]]*#?[[:space:]]*" key "([[:space:]]|$)" && !done {
            print key sep value; done=1; next
        }
        { print }
        END { if (!done) print key sep value }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

service_active() {
    command_exists systemctl && systemctl is-active --quiet "$1"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: kernel — sysctl hardening and protocol blacklist
# ═══════════════════════════════════════════════════════════════════════════════

KERNEL_SYSCTL_FILE="/etc/sysctl.d/90-hardening.conf"
KERNEL_MODULE_FILE="/etc/modprobe.d/blacklist-uncommon-net.conf"

kernel_has_bluetooth() {
    [ -d /sys/class/bluetooth ] && ls /sys/class/bluetooth/* >/dev/null 2>&1
}

kernel_docker_or_virt() {
    command_exists docker || command_exists podman ||
        service_active docker || service_active podman || service_active libvirtd
}

kernel_sysctl_available() {
    [ -e "/proc/sys/$(printf '%s' "$1" | tr '.' '/')" ]
}

kernel_append_sysctl() {
    file=$1; key=$2; val=$3
    kernel_sysctl_available "$key" && printf '%s = %s\n' "$key" "$val" >> "$file"
}

kernel_build_sysctl() {
    tmp=$1
    cat > "$tmp" <<'EOF'
# Managed by linutil security-hardening.sh
EOF
    kernel_append_sysctl "$tmp" "net.core.bpf_jit_harden"              "2"
    kernel_append_sysctl "$tmp" "fs.protected_fifos"                    "2"
    kernel_append_sysctl "$tmp" "fs.protected_regular"                  "2"
    kernel_append_sysctl "$tmp" "fs.suid_dumpable"                      "0"
    kernel_append_sysctl "$tmp" "net.ipv4.conf.all.log_martians"        "1"
    kernel_append_sysctl "$tmp" "net.ipv4.conf.default.log_martians"    "1"

    if ! kernel_docker_or_virt; then
        kernel_append_sysctl "$tmp" "net.ipv4.conf.all.send_redirects"     "0"
        kernel_append_sysctl "$tmp" "net.ipv4.conf.default.send_redirects" "0"
    else
        printf "%b\n" "${YELLOW}Skipping send_redirects: container/virt detected${RC}"
    fi

    if ! kernel_docker_or_virt && ! service_active tailscaled; then
        kernel_append_sysctl "$tmp" "net.ipv4.conf.all.forwarding"      "0"
        kernel_append_sysctl "$tmp" "net.ipv4.conf.default.forwarding"  "0"
    else
        printf "%b\n" "${YELLOW}Skipping forwarding: container tooling or Tailscale detected${RC}"
    fi

    if ! kernel_has_bluetooth; then
        kernel_append_sysctl "$tmp" "dev.tty.ldisc_autoload" "0"
    else
        printf "%b\n" "${YELLOW}Skipping tty ldisc: Bluetooth hardware detected${RC}"
    fi

    kernel_append_sysctl "$tmp" "kernel.unprivileged_bpf_disabled" "1"
}

run_kernel() {
    printf "%b\n" "${CYAN}[kernel] Applying kernel hardening...${RC}"
    sysctl_tmp=$(mktemp); module_tmp=$(mktemp)

    kernel_build_sysctl "$sysctl_tmp"

    cat > "$module_tmp" <<'EOF'
# Managed by linutil security-hardening.sh
install dccp /bin/false
install sctp /bin/false
install rds  /bin/false
install tipc /bin/false
EOF

    write_if_changed "$sysctl_tmp" "$KERNEL_SYSCTL_FILE"
    write_if_changed "$module_tmp" "$KERNEL_MODULE_FILE"
    rm -f "$sysctl_tmp" "$module_tmp"

    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would run: sysctl --load $KERNEL_SYSCTL_FILE${RC}"
    else
        run_root sysctl --load "$KERNEL_SYSCTL_FILE"
    fi
    printf "%b\n" "${GREEN}[kernel] Done.${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: proc — core-dump hardening and /proc isolation
# ═══════════════════════════════════════════════════════════════════════════════

PROC_LIMITS_FILE="/etc/security/limits.d/90-hardening.conf"
PROC_COREDUMP_FILE="/etc/systemd/coredump.conf.d/hardening.conf"
PROC_MOUNT_FILE="/etc/systemd/system/proc.mount.d/hardening.conf"
PROC_TARGET_USER=${SUDO_USER:-$USER}

proc_confirm_hidepid() {
    case "$PROC_HARDENING_HIDEPID" in
        1|true|yes)  return 0 ;;
        0|false|no)  return 1 ;;
    esac
    [ ! -t 0 ] && { printf "%b\n" "${YELLOW}Skipping hidepid=2: no interactive terminal${RC}"; return 1; }
    printf "%b\n" "${YELLOW}hidepid=2 hides other users' processes. Some monitoring tools need the 'proc' group.${RC}"
    printf "%b" "Apply hidepid=2 and add ${PROC_TARGET_USER} to the proc group? (y/N): "
    read -r resp
    case "$resp" in [Yy]*) return 0 ;; *) return 1 ;; esac
}

run_proc() {
    printf "%b\n" "${CYAN}[proc] Applying process hardening...${RC}"

    tmp=$(mktemp)
    cat > "$tmp" <<'EOF'
# Managed by linutil security-hardening.sh
* hard core 0
* soft core 0
EOF
    write_if_changed "$tmp" "$PROC_LIMITS_FILE"; rm -f "$tmp"

    tmp=$(mktemp)
    cat > "$tmp" <<'EOF'
[Coredump]
Storage=none
ProcessSizeMax=0
EOF
    write_if_changed "$tmp" "$PROC_COREDUMP_FILE"; rm -f "$tmp"

    if command_exists systemctl; then
        [ "$DRY_RUN" = "1" ] \
            && printf "%b\n" "${CYAN}[DRY RUN] Would run: systemctl daemon-reload${RC}" \
            || run_root systemctl daemon-reload
    fi

    if command_exists systemctl && proc_confirm_hidepid; then
        getent group proc >/dev/null 2>&1 || run_root groupadd proc
        id -nG "$PROC_TARGET_USER" | grep -qw proc || run_root usermod -a -G proc "$PROC_TARGET_USER"

        tmp=$(mktemp)
        cat > "$tmp" <<'EOF'
[Mount]
Options=nosuid,nodev,noexec,relatime,hidepid=2,gid=proc
EOF
        write_if_changed "$tmp" "$PROC_MOUNT_FILE"; rm -f "$tmp"

        if [ "$DRY_RUN" = "1" ]; then
            printf "%b\n" "${CYAN}[DRY RUN] Would remount /proc with hidepid=2${RC}"
        else
            proc_gid=$(getent group proc | awk -F: '{print $3}')
            run_root systemctl daemon-reload
            run_root mount -o remount,nosuid,nodev,noexec,relatime,hidepid=2,gid="$proc_gid" /proc
        fi
    fi
    printf "%b\n" "${GREEN}[proc] Done.${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: pam — password policy and login.defs
# ═══════════════════════════════════════════════════════════════════════════════

PAM_PWQUALITY_FILE="/etc/security/pwquality.conf"
PAM_LOGIN_DEFS_FILE="/etc/login.defs"

run_pam() {
    printf "%b\n" "${CYAN}[pam] Applying PAM hardening...${RC}"

    printf "%b\n" "${YELLOW}Installing password quality tooling...${RC}"
    case "$PACKAGER" in
        pacman)       run_root "$PACKAGER" -S --needed --noconfirm libpwquality ;;
        apt-get|nala) run_root "$PACKAGER" install -y libpam-pwquality ;;
        dnf)          run_root "$PACKAGER" install -y libpwquality ;;
        zypper)       run_root "$PACKAGER" install -y pam_pwquality ;;
        apk)          run_root "$PACKAGER" add libpwquality ;;
        xbps-install) run_root "$PACKAGER" -Sy libpwquality ;;
        eopkg)        run_root "$PACKAGER" install -y libpwquality ;;
        *) printf "%b\n" "${YELLOW}No pwquality package mapping for $PACKAGER; skipping install${RC}" ;;
    esac

    if [ -f "$PAM_LOGIN_DEFS_FILE" ]; then
        tmp=$(mktemp); cp "$PAM_LOGIN_DEFS_FILE" "$tmp"
        case "$DTYPE" in alpine) enc="SHA512" ;; *) enc="YESCRYPT" ;; esac
        update_config_key "$tmp" "UMASK"          "027" "	"
        update_config_key "$tmp" "PASS_MAX_DAYS"  "365" "	"
        update_config_key "$tmp" "PASS_MIN_DAYS"  "1"   "	"
        update_config_key "$tmp" "ENCRYPT_METHOD" "$enc" "	"
        write_if_changed "$tmp" "$PAM_LOGIN_DEFS_FILE"; rm -f "$tmp"
        printf "%b\n" "${CYAN}PASS_MAX_DAYS/MIN_DAYS affect new password changes only.${RC}"
    fi

    tmp=$(mktemp)
    cat > "$tmp" <<'EOF'
# Managed by linutil security-hardening.sh
minlen  = 12
dcredit = -1
ucredit = -1
lcredit = -1
ocredit = -1
EOF
    write_if_changed "$tmp" "$PAM_PWQUALITY_FILE"; rm -f "$tmp"
    printf "%b\n" "${GREEN}[pam] Done.${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: auditd — audit rules
# ═══════════════════════════════════════════════════════════════════════════════

AUDITD_RULES_FILE="/etc/audit/rules.d/99-hardening.rules"

run_auditd() {
    printf "%b\n" "${CYAN}[auditd] Setting up audit rules...${RC}"

    if ! command_exists auditctl; then
        printf "%b\n" "${YELLOW}Installing auditd...${RC}"
        case "$PACKAGER" in
            pacman)       run_root "$PACKAGER" -S --needed --noconfirm audit ;;
            apt|apt-get)  run_root "$PACKAGER" install -y auditd audispd-plugins ;;
            dnf)          run_root "$PACKAGER" install -y audit ;;
            apk)          run_root "$PACKAGER" add audit ;;
            xbps-install) run_root "$PACKAGER" -Sy audit ;;
            *) printf "%b\n" "${RED}Unsupported package manager for auditd: $PACKAGER${RC}"; return 1 ;;
        esac
    fi

    if [ -f "$AUDITD_RULES_FILE" ] && grep -q "Managed by linutil" "$AUDITD_RULES_FILE" 2>/dev/null; then
        printf "%b\n" "${GREEN}Audit rules already deployed${RC}"
    else
        if [ "$DRY_RUN" = "1" ]; then
            printf "%b\n" "${CYAN}[DRY RUN] Would write $AUDITD_RULES_FILE${RC}"
        else
            run_root mkdir -p /etc/audit/rules.d
            run_root tee "$AUDITD_RULES_FILE" > /dev/null <<'EOF'
# Managed by linutil security-hardening.sh
# Covers: exec, access denials, deletions, priv-esc, identity files,
#         sudoers, SSH config, kernel modules, network config, connections.
-D
-b 8192
-f 1
-a always,exit -F arch=b64 -S execve -F key=exec
-a always,exit -F arch=b64 -S open,openat,openat2 -F exit=-EACCES -F key=access
-a always,exit -F arch=b64 -S open,openat,openat2 -F exit=-EPERM  -F key=access
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F key=delete
-w /usr/bin/sudo  -p x  -k priv_esc
-w /bin/su        -p x  -k priv_esc
-w /etc/passwd    -p wa -k identity
-w /etc/group     -p wa -k identity
-w /etc/shadow    -p wa -k identity
-w /etc/sudoers   -p wa -k sudoers
-w /etc/sudoers.d/-p wa -k sudoers
-w /etc/ssh/sshd_config -p wa -k sshd_config_changes
-w /root/.ssh           -p wa -k root_ssh_key_changes
-a always,exit -F arch=b64 -S init_module,delete_module -F key=modules
-w /sbin/insmod   -p x -k modules
-w /sbin/rmmod    -p x -k modules
-w /sbin/modprobe -p x -k modules
-w /etc/hosts     -p wa -k network_modifications
-w /etc/hostname  -p wa -k network_modifications
-w /etc/sysctl.conf -p wa -k network_modifications
-w /etc/sysctl.d/   -p wa -k network_modifications
-a always,exit -F arch=b64 -S socket -S connect -F a1!=2 -F key=network_connections
-e 2
EOF
        fi
    fi

    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would enable auditd${RC}"
    elif service_active auditd; then
        run_root auditctl -R "$AUDITD_RULES_FILE" || true
    else
        run_root systemctl enable --now auditd
    fi
    printf "%b\n" "${GREEN}[auditd] Done. View events with: sudo ausearch -k <keyword>${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: aide — filesystem integrity monitoring
# ═══════════════════════════════════════════════════════════════════════════════

run_aide() {
    printf "%b\n" "${CYAN}[aide] Setting up AIDE...${RC}"

    if ! command_exists aide; then
        printf "%b\n" "${YELLOW}Installing AIDE...${RC}"
        case "$PACKAGER" in
            pacman)         run_root "$PACKAGER" -S --needed --noconfirm aide ;;
            apt-get|nala)   run_root "$PACKAGER" update >/dev/null 2>&1; run_root "$PACKAGER" install -y aide ;;
            dnf)            run_root "$PACKAGER" install -y aide ;;
            zypper)         run_root "$PACKAGER" install -y aide ;;
            apk)            run_root "$PACKAGER" add aide ;;
            xbps-install)   run_root "$PACKAGER" -Sy aide ;;
            *) printf "%b\n" "${RED}Unsupported package manager for AIDE: $PACKAGER${RC}"; return 1 ;;
        esac
    fi

    command_exists aide && aide --version >/dev/null 2>&1 \
        || { printf "%b\n" "${RED}AIDE binary not working; skipping${RC}"; return 1; }

    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would run: aide --config-check${RC}"
    else
        run_root aide --config-check >/dev/null 2>&1 || true
    fi

    AIDE_CONF="${AIDE_CONF:-/etc/aide.conf}"
    DB_IN=$(run_root grep "^database_in" "$AIDE_CONF" 2>/dev/null | sed 's|.*file:||' | head -1)
    DB_OUT=$(run_root grep "^database_out" "$AIDE_CONF" 2>/dev/null | grep -v "^#" | sed 's|.*file:||' | head -1)
    if printf '%s' "${DB_IN}" | grep -q "@@{DBDIR}"; then
        DBDIR=$(run_root grep "^@@define DBDIR" "$AIDE_CONF" 2>/dev/null | awk '{print $3}' | head -1)
        DBDIR="${DBDIR:-/var/lib/aide}"
        DB_IN=$(printf '%s' "$DB_IN"  | sed "s|@@{DBDIR}|$DBDIR|")
        DB_OUT=$(printf '%s' "$DB_OUT" | sed "s|@@{DBDIR}|$DBDIR|")
    fi
    DB_IN="${DB_IN:-/var/lib/aide/aide.db.gz}"
    DB_OUT="${DB_OUT:-/var/lib/aide/aide.db.new.gz}"

    if run_root test -f "$DB_IN" 2>/dev/null; then
        printf "%b\n" "${GREEN}AIDE database already exists at $DB_IN${RC}"
    elif [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would initialise AIDE database${RC}"
    else
        printf "%b\n" "${YELLOW}Initialising AIDE database (this may take several minutes)...${RC}"
        run_root aide --init
        run_root cp "$DB_OUT" "$DB_IN"
    fi

    if command_exists systemctl; then
        if [ "$DRY_RUN" = "1" ]; then
            printf "%b\n" "${CYAN}[DRY RUN] Would enable aidecheck.timer${RC}"
        elif systemctl list-unit-files aidecheck.timer >/dev/null 2>&1; then
            run_root systemctl enable --now aidecheck.timer
        else
            AIDE_BIN=$(command -v aide)
            CRON_FILE="/etc/cron.d/aide-daily"
            run_root test -f "$CRON_FILE" 2>/dev/null \
                || printf '0 5 * * * root %s --check 2>&1 | logger -t aide\n' "$AIDE_BIN" \
                   | run_root tee "$CRON_FILE" >/dev/null
        fi
    fi
    printf "%b\n" "${GREEN}[aide] Done. Run 'sudo aide --check' to verify integrity.${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: clamav — antivirus
# ═══════════════════════════════════════════════════════════════════════════════

run_clamav() {
    printf "%b\n" "${CYAN}[clamav] Setting up ClamAV...${RC}"

    if ! command_exists clamscan; then
        printf "%b\n" "${YELLOW}Installing ClamAV...${RC}"
        case "$PACKAGER" in
            pacman)         run_root "$PACKAGER" -S --needed --noconfirm clamav ;;
            apt-get|nala)   run_root "$PACKAGER" update >/dev/null 2>&1; run_root "$PACKAGER" install -y clamav clamav-daemon ;;
            dnf)            run_root "$PACKAGER" install -y clamav clamav-update ;;
            zypper)         run_root "$PACKAGER" install -y clamav ;;
            apk)            run_root "$PACKAGER" add clamav clamav-daemon ;;
            xbps-install)   run_root "$PACKAGER" -Sy clamav ;;
            eopkg)          run_root "$PACKAGER" install -y clamav ;;
            *)              run_root "$PACKAGER" install -y clamav ;;
        esac
    fi

    if command_exists freshclam; then
        printf "%b\n" "${YELLOW}Updating ClamAV signatures...${RC}"
        run_root freshclam || printf "%b\n" "${YELLOW}freshclam reported an error; rerun later.${RC}"
    fi

    CLAMD_CONF=""
    for f in /etc/clamav/clamd.conf /etc/clamd.d/scan.conf /etc/clamd.conf; do
        [ -f "$f" ] && { CLAMD_CONF="$f"; break; }
    done
    if [ -n "$CLAMD_CONF" ]; then
        printf "%b\n" "${YELLOW}Applying resource limits to $CLAMD_CONF...${RC}"
        for setting in "MaxThreads 2" "MaxRecursion 10" "MaxFiles 10000" \
                       "MaxFileSize 25M" "MaxScanSize 100M" \
                       "ConcurrentDatabaseReload no" "OnAccessScanning no"; do
            key="${setting%% *}"
            run_root sed -i "/^#*[[:space:]]*${key}[[:space:]]/d" "$CLAMD_CONF"
            printf '%s\n' "$setting" | run_root tee -a "$CLAMD_CONF" >/dev/null
        done
    fi

    if command_exists systemctl; then
        for svc in clamav-freshclam.service freshclam.service; do
            systemctl list-unit-files 2>/dev/null | grep -q "^$svc" \
                && { run_root systemctl enable --now "$svc"; break; }
        done
        for svc in clamav-daemon.service clamd.service; do
            systemctl list-unit-files 2>/dev/null | grep -q "^$svc" \
                && { run_root systemctl enable --now "$svc"; break; }
        done
    fi

    checkFlatpak 2>/dev/null || true
    if command_exists flatpak && ! flatpak info io.github.linx_systems.ClamUI >/dev/null 2>&1; then
        flatpak install flathub io.github.linx_systems.ClamUI --user -y || true
    fi

    printf "%b\n" "${GREEN}[clamav] Done. Use ClamUI with the 'System ClamAV' backend.${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: firewall — UFW or FirewallD
# ═══════════════════════════════════════════════════════════════════════════════

run_firewall() {
    printf "%b\n" "${CYAN}[firewall] Configuring firewall (profile: $HARDENING_PROFILE)...${RC}"

    if command_exists firewall-cmd; then
        command_exists systemctl && run_root systemctl enable --now firewalld

        case "$HARDENING_PROFILE" in
            desktop)
                run_root firewall-cmd --set-default-zone=public
                for svc in ssh http https; do
                    run_root firewall-cmd --permanent --query-service="$svc" >/dev/null 2>&1 \
                        && run_root firewall-cmd --permanent --remove-service="$svc" || true
                done
                run_root firewall-cmd --reload
                printf "%b\n" "${GREEN}Desktop firewall defaults applied. No inbound services opened automatically.${RC}"
                ;;
            *)
                run_root firewall-cmd --set-default-zone=public
                run_root firewall-cmd --permanent --add-service=ssh
                for proto in ipv4 ipv6; do
                    run_root firewall-cmd --permanent --direct --add-rule "$proto" filter INPUT_direct 0 \
                        -p tcp --dport 22 -m state --state NEW -m recent --set
                    run_root firewall-cmd --permanent --direct --add-rule "$proto" filter INPUT_direct 1 \
                        -p tcp --dport 22 -m state --state NEW -m recent --update \
                        --seconds 30 --hitcount 6 -j REJECT --reject-with tcp-reset
                done
                run_root firewall-cmd --permanent --add-service=http
                run_root firewall-cmd --permanent --add-service=https
                run_root firewall-cmd --reload
                printf "%b\n" "${GREEN}CTT firewall baseline applied.${RC}"
                ;;
        esac
    else
        command_exists ufw || {
            printf "%b\n" "${YELLOW}Installing UFW...${RC}"
            case "$PACKAGER" in
                pacman)       run_root "$PACKAGER" -S --needed --noconfirm ufw ;;
                apk)          run_root "$PACKAGER" add ufw ;;
                xbps-install) run_root "$PACKAGER" -Sy ufw ;;
                *)            run_root "$PACKAGER" install -y ufw ;;
            esac
        }
        run_root ufw --force disable

        case "$HARDENING_PROFILE" in
            desktop)
                run_root ufw logging medium
                run_root ufw default deny incoming
                run_root ufw default deny routed
                run_root ufw default allow outgoing
                run_root ufw --force enable
                printf "%b\n" "${GREEN}Desktop UFW defaults applied. No inbound services opened automatically.${RC}"
                ;;
            *)
                run_root ufw limit 22/tcp
                run_root ufw allow 80/tcp
                run_root ufw allow 443/tcp
                run_root ufw default deny incoming
                run_root ufw default allow outgoing
                run_root ufw enable
                printf "%b\n" "${GREEN}CTT UFW baseline applied.${RC}"
                ;;
        esac
    fi
    printf "%b\n" "${GREEN}[firewall] Done.${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: ssh — harden sshd_config
# ═══════════════════════════════════════════════════════════════════════════════

SSH_CONFIG="/etc/ssh/sshd_config"

ssh_restart() {
    command_exists systemctl || return 0
    service_active sshd && { run_root systemctl restart sshd; return; }
    service_active ssh  &&   run_root systemctl restart ssh
}

run_ssh() {
    if ! command_exists sshd || [ ! -f "$SSH_CONFIG" ]; then
        printf "%b\n" "${YELLOW}[ssh] sshd not installed; skipping${RC}"; return 0
    fi
    printf "%b\n" "${CYAN}[ssh] Hardening sshd_config...${RC}"

    tmp=$(mktemp)
    cp "$SSH_CONFIG" "$tmp"
    update_config_key "$tmp" "AllowTcpForwarding"   "no"
    update_config_key "$tmp" "AllowAgentForwarding" "no"
    update_config_key "$tmp" "ClientAliveCountMax"  "2"
    update_config_key "$tmp" "MaxAuthTries"         "3"
    update_config_key "$tmp" "MaxSessions"          "2"
    update_config_key "$tmp" "LogLevel"             "VERBOSE"
    update_config_key "$tmp" "TCPKeepAlive"         "no"
    update_config_key "$tmp" "PrintLastLog"         "yes"

    if cmp -s "$tmp" "$SSH_CONFIG"; then
        printf "%b\n" "${GREEN}$SSH_CONFIG already matches hardened baseline${RC}"
        rm -f "$tmp"; return 0
    fi

    if [ "$DRY_RUN" = "1" ]; then
        cat "$tmp"; printf "%b\n" "${CYAN}[DRY RUN] Would validate with: sshd -t${RC}"
        rm -f "$tmp"; return 0
    fi

    backup="${SSH_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
    run_root cp "$SSH_CONFIG" "$backup"
    run_root cp "$tmp" "$SSH_CONFIG"
    rm -f "$tmp"

    if ! run_root sshd -t; then
        printf "%b\n" "${RED}sshd validation failed; restoring backup${RC}"
        run_root cp "$backup" "$SSH_CONFIG"; exit 1
    fi
    ssh_restart

    if grep -Eq '^[[:space:]]*Port[[:space:]]+22([[:space:]]|$)' "$SSH_CONFIG" \
       && ! service_active tailscaled; then
        printf "%b\n" "${CYAN}Tip: consider moving SSH off port 22 and using a VPN or tighter firewall rules.${RC}"
    fi
    printf "%b\n" "${GREEN}[ssh] Done.${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: banner — login banner
# ═══════════════════════════════════════════════════════════════════════════════

BANNER_ISSUE="/etc/issue"
BANNER_ISSUE_NET="/etc/issue.net"

run_banner() {
    printf "%b\n" "${CYAN}[banner] Configuring login banner...${RC}"

    tmp=$(mktemp)
    cat > "$tmp" <<'EOF'
*******************************************************************************
NOTICE: This system is for authorized use only. Unauthorized access or use
is prohibited and may result in disciplinary action and/or civil and criminal
penalties. All activity on this system may be monitored and recorded.
*******************************************************************************
EOF
    write_if_changed "$tmp" "$BANNER_ISSUE"
    write_if_changed "$tmp" "$BANNER_ISSUE_NET"
    rm -f "$tmp"

    if command_exists sshd && [ -f "$SSH_CONFIG" ]; then
        tmp=$(mktemp); cp "$SSH_CONFIG" "$tmp"
        update_config_key "$tmp" "Banner" "$BANNER_ISSUE_NET"
        if ! cmp -s "$tmp" "$SSH_CONFIG"; then
            if [ "$DRY_RUN" = "1" ]; then
                printf "%b\n" "${CYAN}[DRY RUN] Would set SSH Banner${RC}"
            else
                backup="${SSH_CONFIG}.bak.$(date +%Y%m%d_%H%M%S)"
                run_root cp "$SSH_CONFIG" "$backup"
                run_root cp "$tmp" "$SSH_CONFIG"
                run_root sshd -t
                ssh_restart
            fi
        fi
        rm -f "$tmp"
    fi
    printf "%b\n" "${GREEN}[banner] Done.${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: apparmor — mandatory access control
# ═══════════════════════════════════════════════════════════════════════════════

AA_LSM_ORDER="landlock,lockdown,yama,integrity,apparmor,bpf"
AA_BOOTLOADER=""
AA_BACKUP_FILE=""
AA_TARGET_CONFIG=""
AA_UPDATED=false

aa_cleanup() {
    if [ "$AA_UPDATED" = "false" ] && [ -n "$AA_BACKUP_FILE" ] && \
       [ -f "$AA_BACKUP_FILE" ] && [ -n "$AA_TARGET_CONFIG" ]; then
        printf "%b\n" "${YELLOW}Unexpected exit — restoring ${AA_TARGET_CONFIG} from backup...${RC}"
        cp "$AA_BACKUP_FILE" "$AA_TARGET_CONFIG" \
            && printf "%b\n" "${GREEN}✓ Backup restored${RC}"
    fi
}

aa_merge_lsm() {
    awk -v order="$AA_LSM_ORDER" '
    {
        out=""; have=0; n=split($0,toks,/[[:space:]]+/)
        for(i=1;i<=n;i++){
            t=toks[i]; if(t=="") continue
            if(t~/^lsm=/){
                have=1; val=substr(t,5)
                if(val!~/(^|,)apparmor(,|$)/) val=val",apparmor"
                t="lsm="val
            }
            out=(out==""?t:out" "t)
        }
        if(!have) out=(out==""?"lsm="order:out" lsm="order)
        print out
    }'
}

aa_has_token() {
    awk '{for(i=1;i<=NF;i++) if($i~/^lsm=/ && substr($i,5)~/(^|,)apparmor(,|$)/) exit 0; exit 1}'
}

aa_detect_bootloader() {
    if command_exists bootctl; then
        cur=$(bootctl status 2>/dev/null \
            | awk '/Current Boot Loader/{getline;print}' \
            | awk -F: '{print $2}' | tr -d ' ')
        case "$cur" in
            *Limine*)          AA_BOOTLOADER="limine";       return ;;
            *systemd-boot*)    AA_BOOTLOADER="systemd-boot"; return ;;
            *GRUB*|*grub*)     AA_BOOTLOADER="grub";         return ;;
            *rEFInd*|*refind*) AA_BOOTLOADER="refind";       return ;;
        esac
    fi
    if [ -f /etc/default/limine ] || command_exists limine-update; then
        AA_BOOTLOADER="limine"; return
    fi
    if [ -d /boot/loader/entries ] || [ -f /etc/kernel/cmdline ]; then
        AA_BOOTLOADER="systemd-boot"; return
    fi
    [ -f /etc/default/grub ] && { AA_BOOTLOADER="grub"; return; }
    if [ -f /boot/refind_linux.conf ] || [ -f /boot/EFI/refind/refind.conf ]; then
        AA_BOOTLOADER="refind"; return
    fi
    AA_BOOTLOADER="unknown"
}

aa_setup_limine() {
    AA_TARGET_CONFIG="/etc/default/limine"
    [ -f "$AA_TARGET_CONFIG" ] || { printf "%b\n" "${RED}$AA_TARGET_CONFIG not found.${RC}"; exit 1; }
    if grep -q 'lsm=[^"]*apparmor' "$AA_TARGET_CONFIG"; then
        printf "%b\n" "${GREEN}✓ Limine already has apparmor in lsm=.${RC}"
    else
        AA_BACKUP_FILE="${AA_TARGET_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$AA_TARGET_CONFIG" "$AA_BACKUP_FILE"
        if grep -qE '^KERNEL_CMDLINE\[default\].*lsm=' "$AA_TARGET_CONFIG"; then
            awk '/^KERNEL_CMDLINE\[default\].*lsm=/ && !done {
                if(match($0,/lsm=[^ "'"'"']+/)){
                    tok=substr($0,RSTART,RLENGTH); val=substr(tok,5)
                    if(val!~/(^|,)apparmor(,|$)/){
                        $0=substr($0,1,RSTART-1) "lsm=" val ",apparmor" substr($0,RSTART+RLENGTH)
                    }
                    done=1
                }
            } {print}' "$AA_BACKUP_FILE" > "$AA_TARGET_CONFIG"
        else
            printf '\n# Added by linutil\nKERNEL_CMDLINE[default]+="lsm=%s"\n' \
                "$AA_LSM_ORDER" >> "$AA_TARGET_CONFIG"
        fi
        printf "%b\n" "${GREEN}✓ Limine config updated.${RC}"
    fi
    command_exists limine-update || { printf "%b\n" "${RED}limine-update not found.${RC}"; exit 1; }
    limine-update; AA_UPDATED=true
}

aa_setup_systemd_boot() {
    if [ -f /etc/kernel/cmdline ]; then
        AA_TARGET_CONFIG="/etc/kernel/cmdline"
        AA_BACKUP_FILE="${AA_TARGET_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$AA_TARGET_CONFIG" "$AA_BACKUP_FILE"
        cur=$(tr -d '\n' < "$AA_TARGET_CONFIG")
        if ! printf '%s\n' "$cur" | aa_has_token; then
            printf '%s\n' "$cur" | aa_merge_lsm > "$AA_TARGET_CONFIG"
            printf "%b\n" "${GREEN}✓ /etc/kernel/cmdline updated.${RC}"
        fi
        command_exists reinstall-kernels && { reinstall-kernels; AA_UPDATED=true; return; }
        if command_exists kernel-install; then
            find /lib/modules -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while IFS= read -r k; do
                ver=$(basename "$k")
                [ -f "$k/vmlinuz" ] && kernel-install add "$ver" "$k/vmlinuz" || true
            done
        elif command_exists mkinitcpio; then
            mkinitcpio -P
        fi
        AA_UPDATED=true; return
    fi
    if [ -d /boot/loader/entries ]; then
        AA_TARGET_CONFIG="/boot/loader/entries"
        AA_BACKUP_FILE="${AA_TARGET_CONFIG}.backup.$(date +%Y%m%d_%H%M%S).tar"
        tar -cf "$AA_BACKUP_FILE" -C /boot/loader entries
        changed=0
        for entry in /boot/loader/entries/*.conf; do
            [ -f "$entry" ] || continue
            case "$(basename "$entry")" in *snapshot*|*rollback*) continue ;; esac
            opts=$(awk '/^options /{sub(/^options[[:space:]]+/,""); print; exit}' "$entry")
            [ -z "$opts" ] && continue
            printf '%s\n' "$opts" | aa_has_token && continue
            new=$(printf '%s\n' "$opts" | aa_merge_lsm)
            tmp=$(mktemp)
            awk -v new="$new" '/^options /{print "options " new; next} {print}' "$entry" > "$tmp"
            mv "$tmp" "$entry"; changed=$((changed+1))
        done
        printf "%b\n" "${GREEN}✓ systemd-boot: updated $changed entries.${RC}"
        command_exists bootctl && bootctl update 2>/dev/null || true
        AA_UPDATED=true; return
    fi
    printf "%b\n" "${RED}systemd-boot detected but no config source found.${RC}"; exit 1
}

aa_setup_grub() {
    AA_TARGET_CONFIG="/etc/default/grub"
    [ -f "$AA_TARGET_CONFIG" ] || { printf "%b\n" "${RED}$AA_TARGET_CONFIG not found.${RC}"; exit 1; }
    grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$AA_TARGET_CONFIG" \
        || { printf "%b\n" "${RED}GRUB_CMDLINE_LINUX_DEFAULT not found.${RC}"; exit 1; }
    cur=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$AA_TARGET_CONFIG" | head -1 | cut -d'"' -f2)
    if ! printf '%s\n' "$cur" | aa_has_token; then
        AA_BACKUP_FILE="${AA_TARGET_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$AA_TARGET_CONFIG" "$AA_BACKUP_FILE"
        new=$(printf '%s\n' "$cur" | aa_merge_lsm | sed 's/^[[:space:]]*//')
        tmp=$(mktemp)
        awk -v new="$new" \
            '/^GRUB_CMDLINE_LINUX_DEFAULT=/ && !done {print "GRUB_CMDLINE_LINUX_DEFAULT=\"" new "\""; done=1; next} {print}' \
            "$AA_TARGET_CONFIG" > "$tmp"
        mv "$tmp" "$AA_TARGET_CONFIG"
        printf "%b\n" "${GREEN}✓ GRUB cmdline updated.${RC}"
    fi
    grub_cfg=""
    for p in /boot/grub/grub.cfg /boot/grub2/grub.cfg; do [ -f "$p" ] && { grub_cfg="$p"; break; }; done
    if command_exists update-grub; then update-grub
    elif command_exists grub-mkconfig  && [ -n "$grub_cfg" ]; then grub-mkconfig  -o "$grub_cfg"
    elif command_exists grub2-mkconfig && [ -n "$grub_cfg" ]; then grub2-mkconfig -o "$grub_cfg"
    else printf "%b\n" "${RED}No GRUB regen command found. Run grub-mkconfig manually.${RC}"; exit 1
    fi
    AA_UPDATED=true
}

aa_setup_refind() {
    if   [ -f /boot/refind_linux.conf ];          then AA_TARGET_CONFIG="/boot/refind_linux.conf"
    elif [ -f /boot/EFI/refind/refind.conf ];     then AA_TARGET_CONFIG="/boot/EFI/refind/refind.conf"
    else printf "%b\n" "${RED}No rEFInd config found.${RC}"; exit 1; fi
    AA_BACKUP_FILE="${AA_TARGET_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$AA_TARGET_CONFIG" "$AA_BACKUP_FILE"
    if ! grep -q 'lsm=[^"]*apparmor' "$AA_TARGET_CONFIG"; then
        tmp=$(mktemp)
        awk -v order="$AA_LSM_ORDER" '
        function merge_q(line,    m,inside) {
            if(match(line,/"[^"]*"/)){
                inside=substr(line,RSTART+1,RLENGTH-2)
                if(inside~/lsm=[^ ]*/){ if(inside!~/lsm=[^ ]*apparmor/) sub(/lsm=[^ ]*/,"&,apparmor",inside) }
                else inside=inside " lsm=" order
                return substr(line,1,RSTART-1) "\"" inside "\"" substr(line,RSTART+RLENGTH)
            }
            return line
        }
        /^"[^"]*"[[:space:]]+"/ || /^[[:space:]]*options[[:space:]]+/ { print merge_q($0); next }
        { print }' "$AA_TARGET_CONFIG" > "$tmp"
        mv "$tmp" "$AA_TARGET_CONFIG"
        printf "%b\n" "${GREEN}✓ rEFInd config updated.${RC}"
    fi
    AA_UPDATED=true
}

aa_install_profiles() {
    case "$PACKAGER" in
        pacman)
            if ! pacman -Qi apparmor.d-git >/dev/null 2>&1 && ! pacman -Qi apparmor.d >/dev/null 2>&1; then
                if pacman -Si apparmor.d-git >/dev/null 2>&1; then
                    run_root "$PACKAGER" -S --needed --noconfirm apparmor.d-git
                elif pacman -Si apparmor.d >/dev/null 2>&1; then
                    run_root "$PACKAGER" -S --needed --noconfirm apparmor.d
                elif [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
                    checkAURHelper
                    su - "$SUDO_USER" -c "$AUR_HELPER -S --noconfirm apparmor.d-git"
                else
                    printf "%b\n" "${RED}Cannot install AUR package as root without SUDO_USER.${RC}"
                fi
                if [ -f /etc/apparmor/parser.conf ] && ! grep -q '^cache-loc' /etc/apparmor/parser.conf; then
                    mkdir -p /etc/apparmor/earlypolicy/
                    printf '\ncache-loc /etc/apparmor/earlypolicy/\nwrite-cache\n' >> /etc/apparmor/parser.conf
                fi
            fi
            ;;
        apt|apt-get) run_root "$PACKAGER" install -y apparmor-profiles apparmor-profiles-extra || true ;;
        zypper)      run_root "$PACKAGER" install -y apparmor-profiles || true ;;
        dnf|yum)     printf "%b\n" "${CYAN}Fedora: extended profiles bundled with base apparmor pkg.${RC}" ;;
        *)           printf "%b\n" "${YELLOW}No extended profile mapping for $PACKAGER; skipping.${RC}" ;;
    esac
}

aa_install_appanvil() {
    command_exists appanvil && { printf "%b\n" "${GREEN}✓ AppAnvil already installed.${RC}"; return 0; }
    APPANVIL_URL="https://github.com/TuxLux40/AppAnvil.git"
    printf "%b\n" "${YELLOW}Building AppAnvil from source (${APPANVIL_URL})...${RC}"
    case "$PACKAGER" in
        pacman)      run_root "$PACKAGER" -S --needed --noconfirm cmake base-devel git pkgconf gtkmm3 jsoncpp apparmor ;;
        apt|apt-get) run_root "$PACKAGER" install -y cmake git pkg-config g++ bison flex libgtkmm-3.0-dev libjsoncpp-dev libapparmor-dev apparmor-utils ;;
        dnf|yum)     run_root "$PACKAGER" install -y cmake git gcc-c++ bison flex pkgconf-pkg-config gtkmm30-devel jsoncpp-devel libapparmor-devel ;;
        zypper)      run_root "$PACKAGER" install -y cmake git gcc-c++ bison flex pkg-config gtkmm3-devel jsoncpp-devel libapparmor-devel ;;
        *) printf "%b\n" "${YELLOW}No build-dep mapping for $PACKAGER; install cmake+gtkmm3+jsoncpp+libapparmor manually.${RC}"; return 1 ;;
    esac
    build_user="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
    build_dir=$(mktemp -d -t appanvil.XXXXXX)
    chown "$build_user:$build_user" "$build_dir"
    su - "$build_user" -c "
        set -e
        cd '$build_dir'
        git clone --depth 1 --branch main '$APPANVIL_URL' AppAnvil
        cd AppAnvil
        git submodule update --init --recursive
        cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr .
        make -j\$(nproc)
    " || { printf "%b\n" "${RED}AppAnvil build failed.${RC}"; rm -rf "$build_dir"; return 1; }
    ( cd "$build_dir/AppAnvil" && make install )
    rm -rf "$build_dir"
    command_exists appanvil \
        && printf "%b\n" "${GREEN}✓ AppAnvil installed.${RC}" \
        || printf "%b\n" "${RED}AppAnvil install completed but binary not on PATH.${RC}"
}

run_apparmor() {
    if command_exists getenforce && [ "$(getenforce 2>/dev/null)" != "Disabled" ]; then
        printf "%b\n" "${YELLOW}[apparmor] Native SELinux is active; skipping AppArmor.${RC}"
        return 0
    fi

    command_exists apparmor_parser || {
        printf "%b\n" "${YELLOW}Installing AppArmor...${RC}"
        case "$PACKAGER" in
            pacman)       run_root "$PACKAGER" -S --needed --noconfirm apparmor ;;
            apt|apt-get)  run_root "$PACKAGER" install -y apparmor apparmor-utils ;;
            dnf|yum)      run_root "$PACKAGER" install -y apparmor-parser apparmor-utils ;;
            zypper)       run_root "$PACKAGER" install -y apparmor-parser apparmor-utils ;;
            xbps-install) run_root "$PACKAGER" -Sy apparmor ;;
            *) printf "%b\n" "${RED}Unsupported package manager for AppArmor: $PACKAGER${RC}"; exit 1 ;;
        esac
    }

    cfg=""
    [ -r "/boot/config-$(uname -r)" ] && cfg="/boot/config-$(uname -r)"
    [ -r "/proc/config.gz" ]           && cfg="/proc/config.gz"
    if [ -n "$cfg" ]; then
        cat_cmd=cat; [ "$cfg" = "/proc/config.gz" ] && cat_cmd=zcat
        $cat_cmd "$cfg" | grep -q '^CONFIG_SECURITY_APPARMOR=y' || {
            printf "%b\n" "${RED}Kernel lacks CONFIG_SECURITY_APPARMOR=y. Install an apparmor-capable kernel first.${RC}"
            exit 1
        }
    fi

    aa_detect_bootloader
    printf "%b\n" "${CYAN}[apparmor] Detected bootloader: $AA_BOOTLOADER${RC}"

    printf "%b\n" "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    printf "%b\n" "${RED}  WARNING: MODIFYING BOOTLOADER CONFIG${RC}"
    printf "%b\n" "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
    printf "%b\n" "${YELLOW}This adds apparmor to the kernel lsm= list. Have recovery media ready.${RC}"
    printf "%b\n" "${YELLOW}A timestamped backup of the edited config will be created.${RC}"
    printf "%b" "Type 'I UNDERSTAND THE RISKS' to continue: "
    read -r confirmation
    [ "$confirmation" = "I UNDERSTAND THE RISKS" ] || { printf "%b\n" "${RED}Aborted.${RC}"; return 1; }

    trap aa_cleanup EXIT
    case "$AA_BOOTLOADER" in
        limine)       aa_setup_limine ;;
        systemd-boot) aa_setup_systemd_boot ;;
        grub)         aa_setup_grub ;;
        refind)       aa_setup_refind ;;
        *) printf "%b\n" "${RED}Unsupported bootloader. Add lsm=${AA_LSM_ORDER} to kernel cmdline manually.${RC}"; exit 1 ;;
    esac
    trap - EXIT

    printf "%b\n" "${YELLOW}Installing extended AppArmor profiles...${RC}"
    aa_install_profiles

    aa_install_appanvil || true

    if command_exists systemctl; then
        systemctl is-enabled apparmor.service >/dev/null 2>&1 \
            || run_root systemctl enable apparmor.service
        if service_active apparmor.service; then
            run_root systemctl reload apparmor.service 2>/dev/null \
                || run_root systemctl restart apparmor.service || true
        fi
    fi

    printf "%b\n" "${GREEN}[apparmor] Boot setup complete ($AA_BOOTLOADER). Reboot required.${RC}"
    printf "  cat /sys/kernel/security/lsm   # should list apparmor\n"
    printf "  aa-status                       # lists loaded profiles\n"
    printf "%b\n" "${YELLOW}Backup: ${AA_BACKUP_FILE:-none}${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: usbguard — USB device allowlisting
# ═══════════════════════════════════════════════════════════════════════════════

run_usbguard() {
    printf "%b\n" "${CYAN}[usbguard] Setting up USBGuard...${RC}"
    [ -t 0 ] || { printf "%b\n" "${RED}USBGuard requires an interactive terminal.${RC}"; return 1; }
    printf "%b\n" "${RED}USBGuard will block any USB devices NOT currently connected.${RC}"
    printf "%b\n" "${YELLOW}Ensure keyboard and mouse are already plugged in before proceeding.${RC}"
    printf "%b" "Proceed? (y/N): "
    read -r resp; case "$resp" in [Yy]*) ;; *) printf "%b\n" "${YELLOW}Aborted.${RC}"; return 1 ;; esac

    command_exists usbguard || {
        case "$PACKAGER" in
            pacman)         run_root "$PACKAGER" -S --needed --noconfirm usbguard ;;
            apt-get|nala)   run_root "$PACKAGER" install -y usbguard ;;
            dnf)            run_root "$PACKAGER" install -y usbguard ;;
            zypper)         run_root "$PACKAGER" install -y usbguard ;;
            apk)            run_root "$PACKAGER" add usbguard ;;
            xbps-install)   run_root "$PACKAGER" -Sy usbguard ;;
            eopkg)          run_root "$PACKAGER" install -y usbguard ;;
            *) printf "%b\n" "${RED}Unsupported package manager for USBGuard.${RC}"; exit 1 ;;
        esac
    }

    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would generate USB policy and enable usbguard${RC}"
    else
        tmp=$(mktemp)
        usbguard generate-policy > "$tmp"
        run_root mkdir -p /etc/usbguard
        run_root cp "$tmp" /etc/usbguard/rules.conf
        rm -f "$tmp"
        command_exists systemctl || { printf "%b\n" "${RED}systemctl required to enable USBGuard.${RC}"; exit 1; }
        run_root systemctl enable --now usbguard
    fi
    printf "%b\n" "${GREEN}[usbguard] Done. Authorize future devices with: sudo usbguard allow-device <id>${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: yubikey — YubiKey PAM for sudo/polkit
# ═══════════════════════════════════════════════════════════════════════════════

run_yubikey() {
    printf "%b\n" "${CYAN}[yubikey] Configuring YubiKey PAM...${RC}"
    printf "%b\n" "${YELLOW}This installs pam-u2f, generates U2F keys, and patches /etc/pam.d/sudo.${RC}"
    printf "%b\n" "${RED}Keep a separate root shell open for recovery!${RC}"
    printf "%b" "Proceed? (y/N): "
    read -r resp; case "$resp" in [Yy]*) ;; *) printf "%b\n" "${YELLOW}Aborted.${RC}"; return 1 ;; esac

    case "$PACKAGER" in
        pacman)       run_root "$PACKAGER" -S --noconfirm --needed pam-u2f pcsc-tools pcsclite yubico-pam ;;
        apt-get|nala) run_root "$PACKAGER" update; run_root "$PACKAGER" install -y libpam-u2f pcscd yubikey-manager ;;
        dnf)          run_root "$PACKAGER" install -y pam-u2f pcsc-lite pcsc-tools gnupg2-smime yubikey-manager ;;
        zypper)       run_root "$PACKAGER" install -y pam-u2f pcsc-lite pcsc-tools gnupg2 yubikey-manager ;;
        apk)          run_root "$PACKAGER" add pam-u2f pcsc-lite pcsc-tools gnupg yubikey-manager ;;
        xbps-install) run_root "$PACKAGER" -Sy pam-u2f pcsclite pcsc-tools gnupg2 yubikey-manager ;;
        eopkg)        run_root "$PACKAGER" install -y pam-u2f pcscd yubikey-manager ;;
        *) printf "%b\n" "${RED}Unsupported package manager for YubiKey PAM.${RC}"; exit 1 ;;
    esac

    if command_exists systemctl; then
        run_root systemctl enable --now pcscd.service
        run_root systemctl start pcscd.service
        run_root systemctl is-active --quiet pcscd.service \
            && printf "%b\n" "${GREEN}pcscd running${RC}" \
            || printf "%b\n" "${YELLOW}pcscd may not have started cleanly${RC}"
    fi

    YK_HOME=$(eval echo "~${USER}")
    YK_CFG_DIR="$YK_HOME/.config/Yubico"
    YK_CFG_FILE="$YK_CFG_DIR/u2f_keys"
    mkdir -p "$YK_CFG_DIR"
    pamu2fcfg > "$YK_CFG_FILE"

    run_root sed -i "2i auth sufficient pam_u2f.so authfile=$YK_CFG_FILE cue [prompt=Touch your YubiKey]" /etc/pam.d/sudo
    [ -f /etc/pam.d/polkit-1 ] && \
        run_root sed -i "2i auth sufficient pam_u2f.so authfile=$YK_CFG_FILE cue [prompt=Touch your YubiKey]" /etc/pam.d/polkit-1

    printf "%b\n" "${GREEN}[yubikey] Done. Revert by removing the added lines from /etc/pam.d/sudo.${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: sunshine — port forwarding for game streaming
# ═══════════════════════════════════════════════════════════════════════════════

run_sunshine() {
    printf "%b\n" "${CYAN}[sunshine] Configuring Sunshine port forwarding...${RC}"

    if command_exists ufw; then
        for port in 47984/tcp 47989/tcp 48010/tcp 47998/udp 47999/udp 48000/udp 48002/udp 48010/udp; do
            run_root ufw allow "$port"
        done
    elif command_exists firewall-cmd; then
        for port in 47984/tcp 47989/tcp 48010/tcp 47998/udp 47999/udp 48000/udp 48002/udp 48010/udp; do
            run_root firewall-cmd --permanent --add-port="$port"
        done
        run_root firewall-cmd --reload
    elif command_exists iptables; then
        for port in 47984 47989 48010; do run_root iptables -A INPUT -p tcp --dport "$port" -j ACCEPT; done
        for port in 47998 47999 48000 48002 48010; do run_root iptables -A INPUT -p udp --dport "$port" -j ACCEPT; done
    else
        printf "%b\n" "${RED}No supported firewall found (ufw/firewalld/iptables).${RC}"; return 1
    fi
    printf "%b\n" "${GREEN}[sunshine] Done.${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# MODULE: tailscale — nftables exit-node forwarding fix
# ═══════════════════════════════════════════════════════════════════════════════

TAILSCALE_NFTABLES="/etc/nftables.conf"

tailscale_has_rules() {
    grep -q 'iifname "tailscale0" accept comment "forward from tailnet"' "$TAILSCALE_NFTABLES" &&
    grep -q 'oifname "tailscale0" accept comment "forward to tailnet"'   "$TAILSCALE_NFTABLES"
}

run_tailscale() {
    printf "%b\n" "${CYAN}[tailscale] Applying Tailscale nftables forwarding fix...${RC}"
    checkCommandRequirements "nft awk grep"
    [ -f "$TAILSCALE_NFTABLES" ] || { printf "%b\n" "${RED}Missing $TAILSCALE_NFTABLES.${RC}"; return 1; }

    if tailscale_has_rules; then
        printf "%b\n" "${CYAN}Tailscale forward rules already present in $TAILSCALE_NFTABLES${RC}"
    else
        backup="/etc/nftables.conf.linutil-bak.$(date +%Y%m%d-%H%M%S)"
        run_root cp "$TAILSCALE_NFTABLES" "$backup"

        TMP_FILE=$(run_root mktemp /tmp/linutil-nftables.XXXXXX)
        run_root awk '
            BEGIN{in_forward=0;inserted=0}
            {
                print
                if($0~/^[[:space:]]*chain forward[[:space:]]*\{[[:space:]]*$/){in_forward=1;next}
                if(in_forward && $0~/^[[:space:]]*policy[[:space:]]+drop[[:space:]]*$/ && inserted==0){
                    print ""
                    print "    ct state {established, related} accept comment \"allow forwarded return traffic\""
                    print ""
                    print "    # Required for Tailscale exit node + subnet routing"
                    print "    iifname \"tailscale0\" accept comment \"forward from tailnet\""
                    print "    oifname \"tailscale0\" accept comment \"forward to tailnet\""
                    inserted=1
                }
                if(in_forward && $0~/^[[:space:]]*}/) in_forward=0
            }
            END{if(inserted==0) exit 2}
        ' "$TAILSCALE_NFTABLES" | run_root tee "$TMP_FILE" >/dev/null

        if ! run_root nft -c -f "$TMP_FILE" >/dev/null 2>&1; then
            printf "%b\n" "${RED}Patched config failed syntax check; aborting.${RC}"
            run_root rm -f "$TMP_FILE"; return 1
        fi
        run_root cp "$TMP_FILE" "$TAILSCALE_NFTABLES"
        run_root rm -f "$TMP_FILE"
    fi

    run_root nft -f "$TAILSCALE_NFTABLES"
    run_root nft list chain inet filter forward
    printf "%b\n" "${GREEN}[tailscale] Done.${RC}"
}

# ═══════════════════════════════════════════════════════════════════════════════
# Orchestration
# ═══════════════════════════════════════════════════════════════════════════════

# Modules run by default (desktop hardening set).
DESKTOP_MODULES="kernel proc pam auditd aide clamav firewall ssh banner apparmor"
# Additional opt-in modules available via --all or by name.
ALL_MODULES="$DESKTOP_MODULES usbguard yubikey sunshine tailscale"

run_module() {
    case "$1" in
        kernel)    run_kernel ;;
        proc)      run_proc ;;
        pam)       run_pam ;;
        auditd)    run_auditd ;;
        aide)      run_aide ;;
        clamav)    run_clamav ;;
        firewall)  run_firewall ;;
        ssh)       run_ssh ;;
        banner)    run_banner ;;
        apparmor)  run_apparmor ;;
        usbguard)  run_usbguard ;;
        yubikey)   run_yubikey ;;
        sunshine)  run_sunshine ;;
        tailscale) run_tailscale ;;
        *) printf "%b\n" "${RED}Unknown module: $1${RC}"; exit 1 ;;
    esac
}

main() {
    checkEnv
    checkEscalationTool
    parse_args "$@"

    if [ -n "$REQUESTED_MODULES" ]; then
        for mod in $REQUESTED_MODULES; do run_module "$mod"; done
    elif [ "$RUN_ALL" = "1" ]; then
        for mod in $ALL_MODULES; do run_module "$mod"; done
    else
        printf "%b\n" "${CYAN}Applying desktop hardening baseline (GrapheneOS-inspired defaults)...${RC}"
        printf "%b\n" "${YELLOW}Pass individual module names to run a subset, or --all for everything.${RC}"
        printf "%b\n" "${YELLOW}Available: $ALL_MODULES${RC}"
        printf "\n"
        for mod in $DESKTOP_MODULES; do run_module "$mod"; done
    fi

    printf "\n"
    printf "%b\n" "${GREEN}Security hardening complete.${RC}"
}

main "$@"
