#!/bin/sh

. ../common-script.sh

checkEnv

# ── Helpers ───────────────────────────────────────────────────────────────────

UNIT_DIR="$HOME/.config/systemd/user"

install_sshfs() {
    command_exists sshfs && return 0
    printf "%b\n" "${YELLOW}Installing sshfs...${RC}"
    case "$PACKAGER" in
        pacman)       "$ESCALATION_TOOL" pacman -S --needed --noconfirm sshfs ;;
        apk)          "$ESCALATION_TOOL" apk add sshfs ;;
        xbps-install) "$ESCALATION_TOOL" xbps-install -Sy sshfs ;;
        *)            "$ESCALATION_TOOL" "$PACKAGER" install -y sshfs ;;
    esac
}

# ── Add mount ─────────────────────────────────────────────────────────────────

add_mount() {
    install_sshfs || return 1
    mkdir -p "$UNIT_DIR"

    # allow_other lets apps running as the same user access the mount.
    # Requires user_allow_other in /etc/fuse.conf (one-time system change).
    if [ -f /etc/fuse.conf ] && grep -q '^#user_allow_other' /etc/fuse.conf; then
        "$ESCALATION_TOOL" sed -i 's/^#user_allow_other/user_allow_other/' /etc/fuse.conf
    fi

    printf "\n%b\n" "${YELLOW}--- New SSHFS mount ---${RC}"

    printf "%b" "Remote user [$(id -un)]: "
    read -r RUSER; RUSER=${RUSER:-$(id -un)}

    printf "%b" "Remote host: "
    read -r RHOST
    [ -z "$RHOST" ] && { printf "%b\n" "${RED}Host required${RC}"; return 1; }

    printf "%b" "SSH port [22]: "
    read -r RPORT; RPORT=${RPORT:-22}

    printf "%b" "Remote path [/]: "
    read -r RPATH; RPATH=${RPATH:-/}

    printf "%b" "Local mount point [/mnt/$RHOST]: "
    read -r MPOINT; MPOINT=${MPOINT:-/mnt/$RHOST}

    # Find existing SSH key
    KEYFILE=""
    for k in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ecdsa"; do
        [ -f "$k" ] && { KEYFILE="$k"; break; }
    done

    if [ -n "$KEYFILE" ]; then
        printf "%b" "SSH key [$KEYFILE]: "
    else
        printf "%b" "SSH key (blank to generate one): "
    fi
    read -r K; KEYFILE=${K:-$KEYFILE}

    if [ -z "$KEYFILE" ]; then
        ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" || return 1
        KEYFILE="$HOME/.ssh/id_ed25519"
        printf "%b\n" "${GREEN}Key created at $KEYFILE${RC}"
        printf "%b\n" "${YELLOW}Copy it to the server:  ssh-copy-id -i $KEYFILE $RUSER@$RHOST${RC}"
        printf "%b" "Press Enter after copying..."
        read -r _
    fi

    # Create mount directory (may need escalation for paths outside $HOME)
    mkdir -p "$MPOINT" 2>/dev/null || "$ESCALATION_TOOL" mkdir -p "$MPOINT" || {
        printf "%b\n" "${RED}Cannot create $MPOINT${RC}"; return 1
    }

    # Sanitise hostname into a valid service name (replace non-alphanumeric with -)
    SVC="sshfs-$(printf "%s" "$RHOST" | tr -cs '0-9A-Za-z' '-' | sed 's/^-//;s/-$//')"
    SVC_FILE="$UNIT_DIR/${SVC}.service"

    OPTS="idmap=user,allow_other,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3"
    OPTS="${OPTS},IdentityFile=${KEYFILE},StrictHostKeyChecking=accept-new"
    [ "$RPORT" != "22" ] && OPTS="${OPTS},port=${RPORT}"

    # Type=simple with -f (foreground): systemd manages the process directly.
    # Restart=on-failure retries if the connection drops or the NAS is unreachable.
    cat > "$SVC_FILE" << EOF
[Unit]
Description=SSHFS $RUSER@$RHOST:$RPATH on $MPOINT
After=network.target

[Service]
Type=simple
ExecStart=sshfs $RUSER@$RHOST:$RPATH $MPOINT -f -o $OPTS
ExecStop=/bin/sh -c 'fusermount3 -u $MPOINT 2>/dev/null || fusermount -u $MPOINT 2>/dev/null || true'
Restart=on-failure
RestartSec=30
StartLimitIntervalSec=0

[Install]
WantedBy=default.target
EOF

    systemctl --user daemon-reload
    if systemctl --user enable --now "$SVC"; then
        printf "%b\n" "${GREEN}[OK] $MPOINT will mount at every login${RC}"
    else
        printf "%b\n" "${RED}[FAIL] Could not start service${RC}"
        journalctl --user -u "$SVC" --no-pager -n 20 2>/dev/null || true
        printf "%b\n" "Service file: $SVC_FILE"
    fi
}

# ── List mounts ───────────────────────────────────────────────────────────────

list_mounts() {
    printf "\n%b\n" "${YELLOW}Configured SSHFS services:${RC}"
    FOUND=0
    for SVC_FILE in "$UNIT_DIR"/sshfs-*.service; do
        [ -f "$SVC_FILE" ] || continue
        FOUND=1
        SVC=$(basename "$SVC_FILE" .service)
        STATE=$(systemctl --user is-active "$SVC" 2>/dev/null)
        MP=$(awk '/^ExecStart=/{print $3}' "$SVC_FILE")
        printf "  %-40s %s  [%s]\n" "$SVC" "$MP" "$STATE"
    done
    [ "$FOUND" = 0 ] && printf "%b\n" "${YELLOW}  None configured${RC}"

    printf "\n%b\n" "${YELLOW}Active SSHFS mounts:${RC}"
    if grep -q 'fuse.sshfs' /proc/mounts 2>/dev/null; then
        awk '$3 == "fuse.sshfs" { print "  " $1 " -> " $2 }' /proc/mounts
    else
        printf "%b\n" "${YELLOW}  None active${RC}"
    fi
}

# ── Remove mount ──────────────────────────────────────────────────────────────

remove_mount() {
    SVCS=""
    for SVC_FILE in "$UNIT_DIR"/sshfs-*.service; do
        [ -f "$SVC_FILE" ] || continue
        SVCS="$SVCS $(basename "$SVC_FILE" .service)"
    done

    if [ -z "$SVCS" ]; then
        printf "%b\n" "${YELLOW}No SSHFS services configured${RC}"
        return
    fi

    printf "\n%b\n" "${YELLOW}Select service to remove:${RC}"
    i=1
    for S in $SVCS; do
        MP=$(awk '/^ExecStart=/{print $3}' "$UNIT_DIR/${S}.service")
        printf "  %d) %s  (%s)\n" "$i" "$S" "$MP"
        i=$((i + 1))
    done
    printf "%b" "Number (or Enter to cancel): "
    read -r SEL
    [ -z "$SEL" ] && return

    i=1
    for S in $SVCS; do
        if [ "$i" = "$SEL" ]; then
            systemctl --user disable --now "$S" 2>/dev/null || true
            rm -f "$UNIT_DIR/${S}.service"
            systemctl --user daemon-reload
            printf "%b\n" "${GREEN}[OK] Removed${RC}"
            return
        fi
        i=$((i + 1))
    done
    printf "%b\n" "${RED}Invalid selection${RC}"
}

# ── Main ──────────────────────────────────────────────────────────────────────

while true; do
    printf "\n%b\n" "${YELLOW}=== SSHFS Mount Manager ===${RC}"
    printf "1) Add mount\n"
    printf "2) List mounts\n"
    printf "3) Remove mount\n"
    printf "4) Exit\n"
    printf "%b" "Choice: "
    read -r C
    case "$C" in
        1) add_mount ;;
        2) list_mounts ;;
        3) remove_mount ;;
        4) exit 0 ;;
    esac
done
