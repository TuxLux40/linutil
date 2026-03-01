#!/bin/sh

. ../common-script.sh

checkEnv

AUTOSTART_DIR="$HOME/.config/autostart"
SCRIPTS_DIR="$HOME/.local/bin"

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

add_mount() {
    install_sshfs || return 1

    # allow_other needs user_allow_other in /etc/fuse.conf (one-time)
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

    KEYFILE=""
    for k in "$HOME/.ssh/id_ed25519" "$HOME/.ssh/id_rsa" "$HOME/.ssh/id_ecdsa"; do
        [ -f "$k" ] && { KEYFILE="$k"; break; }
    done
    printf "%b" "SSH key [${KEYFILE:-none found, enter path}]: "
    read -r K; KEYFILE=${K:-$KEYFILE}

    if [ -z "$KEYFILE" ]; then
        ssh-keygen -t ed25519 -f "$HOME/.ssh/id_ed25519" -N "" || return 1
        KEYFILE="$HOME/.ssh/id_ed25519"
        printf "%b\n" "${YELLOW}Copy key to server: ssh-copy-id -i $KEYFILE $RUSER@$RHOST${RC}"
        printf "%b" "Press Enter once done..."
        read -r _
    fi

    mkdir -p "$MPOINT" 2>/dev/null || "$ESCALATION_TOOL" mkdir -p "$MPOINT" || {
        printf "%b\n" "${RED}Cannot create $MPOINT${RC}"; return 1
    }

    OPTS="idmap=user,allow_other,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3"
    OPTS="${OPTS},IdentityFile=${KEYFILE},StrictHostKeyChecking=accept-new"
    [ "$RPORT" != "22" ] && OPTS="${OPTS},port=${RPORT}"

    NAME="sshfs-$(printf "%s" "$RHOST" | tr -cs '0-9A-Za-z' '-' | sed 's/^-//;s/-$//')"
    SCRIPT="$SCRIPTS_DIR/${NAME}.sh"
    DESKTOP="$AUTOSTART_DIR/${NAME}.desktop"

    mkdir -p "$SCRIPTS_DIR" "$AUTOSTART_DIR"

    cat > "$SCRIPT" << EOF
#!/bin/sh
exec sshfs $RUSER@$RHOST:$RPATH $MPOINT -o $OPTS
EOF
    chmod +x "$SCRIPT"

    cat > "$DESKTOP" << EOF
[Desktop Entry]
Type=Application
Name=SSHFS $RHOST
Exec=$SCRIPT
EOF

    printf "%b\n" "${GREEN}[OK] Created:${RC}"
    printf "%b\n" "  $SCRIPT"
    printf "%b\n" "  $DESKTOP"

    printf "%b" "${YELLOW}Mount now? [Y/n]: ${RC}"
    read -r NOW
    if [ -z "$NOW" ] || [ "$NOW" = "y" ] || [ "$NOW" = "Y" ]; then
        if sshfs "$RUSER@$RHOST:$RPATH" "$MPOINT" -o "$OPTS"; then
            printf "%b\n" "${GREEN}[OK] Mounted at $MPOINT${RC}"
        else
            printf "%b\n" "${RED}[FAIL] Check SSH connection. Run manually: $SCRIPT${RC}"
        fi
    fi
}

list_mounts() {
    printf "\n%b\n" "${YELLOW}SSHFS autostart entries:${RC}"
    FOUND=0
    for DF in "$AUTOSTART_DIR"/sshfs-*.desktop; do
        [ -f "$DF" ] || continue
        FOUND=1
        NAME=$(basename "$DF" .desktop)
        MP=$(awk '/^exec sshfs/{print $4; exit}' \
            "$(grep '^Exec=' "$DF" | cut -d= -f2-)" 2>/dev/null)
        printf "  %s  ->  %s\n" "$NAME" "$MP"
    done
    [ "$FOUND" = 0 ] && printf "%b\n" "${YELLOW}  None${RC}"

    printf "\n%b\n" "${YELLOW}Active SSHFS mounts:${RC}"
    if grep -q 'fuse.sshfs' /proc/mounts 2>/dev/null; then
        awk '$3 == "fuse.sshfs" { print "  " $1 " -> " $2 }' /proc/mounts
    else
        printf "%b\n" "${YELLOW}  None${RC}"
    fi
}

remove_mount() {
    NAMES=""
    for DF in "$AUTOSTART_DIR"/sshfs-*.desktop; do
        [ -f "$DF" ] || continue
        NAMES="$NAMES $(basename "$DF" .desktop)"
    done

    if [ -z "$NAMES" ]; then
        printf "%b\n" "${YELLOW}No entries found${RC}"
        return
    fi

    printf "\n%b\n" "${YELLOW}Select entry to remove:${RC}"
    i=1
    for N in $NAMES; do
        printf "  %d) %s\n" "$i" "$N"
        i=$((i + 1))
    done
    printf "%b" "Number (or Enter to cancel): "
    read -r SEL
    [ -z "$SEL" ] && return

    i=1
    for N in $NAMES; do
        if [ "$i" = "$SEL" ]; then
            SCRIPT=$(grep '^Exec=' "$AUTOSTART_DIR/${N}.desktop" | cut -d= -f2-)
            MP=$(awk '/^exec sshfs/{print $4; exit}' "$SCRIPT" 2>/dev/null)
            if [ -n "$MP" ] && grep -q " ${MP} " /proc/mounts 2>/dev/null; then
                fusermount3 -u "$MP" 2>/dev/null || fusermount -u "$MP" 2>/dev/null || true
            fi
            rm -f "$AUTOSTART_DIR/${N}.desktop" "$SCRIPT"
            printf "%b\n" "${GREEN}[OK] Removed${RC}"
            return
        fi
        i=$((i + 1))
    done
    printf "%b\n" "${RED}Invalid selection${RC}"
}

while true; do
    printf "\n%b\n" "${YELLOW}=== SSHFS Mount Manager ===${RC}"
    printf "1) Add mount\n"
    printf "2) List\n"
    printf "3) Remove\n"
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
