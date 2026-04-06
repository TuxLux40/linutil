#! /bin/sh -e

. ../common-script.sh

checkEnv

install_sshfs() {
    command_exists sshfs && return 0
    printf "%b\n" "${YELLOW}Installing sshfs...${RC}"
    case "$PACKAGER" in
        pacman)       "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm sshfs ;;
        apt-get|nala) "$ESCALATION_TOOL" "$PACKAGER" install -y sshfs ;;
        dnf)          "$ESCALATION_TOOL" "$PACKAGER" install -y fuse-sshfs ;;
        xbps-install) "$ESCALATION_TOOL" "$PACKAGER" -Sy sshfs ;;
        apk)          "$ESCALATION_TOOL" "$PACKAGER" add sshfs ;;
        *)            "$ESCALATION_TOOL" "$PACKAGER" install -y sshfs ;;
    esac
}

SYSTEMD_USER_DIR="/home/$(id -un)/.config/systemd/user"

remove_mount() {
    EXISTING=""
    for _f in "$SYSTEMD_USER_DIR"/sshfs-*.service; do
        [ -f "$_f" ] && EXISTING="$EXISTING $_f"
    done
    if [ -z "$EXISTING" ]; then
        printf "%b\n" "${RED}No SSHFS services found.${RC}"
        exit 0
    fi
    printf "%b\n" "${CYAN}Installed SSHFS mounts:${RC}"
    _i=1
    for _f in $EXISTING; do
        _name=$(basename "$_f" .service)
        printf "  %d) %s\n" "$_i" "$_name"
        _i=$((_i + 1))
    done
    printf "%b" "Select number to remove: "
    read -r _sel
    _i=1
    _target=""
    for _f in $EXISTING; do
        [ "$_sel" = "$_i" ] && { _target="$_f"; break; }
        _i=$((_i + 1))
    done
    [ -z "$_target" ] && { printf "%b\n" "${RED}Invalid selection.${RC}"; exit 1; }
    _svcname=$(basename "$_target")
    systemctl --user stop "$_svcname" 2>/dev/null || true
    systemctl --user disable "$_svcname" 2>/dev/null || true
    rm -f "$_target"
    systemctl --user daemon-reload
    printf "%b\n" "${GREEN}Removed $_svcname${RC}"
}

printf "%b\n" "${YELLOW}--- SSHFS Mount Manager ---${RC}"
printf "  1) Add mount\n"
printf "  2) Remove mount\n"
printf "%b" "Select: "
read -r ACTION

if [ "$ACTION" = "2" ]; then
    remove_mount
    exit 0
fi

[ "$ACTION" != "1" ] && { printf "%b\n" "${RED}Invalid selection.${RC}"; exit 1; }

install_sshfs

printf "\n"
printf "%b" "Remote user [$(id -un)]: "
read -r RUSER; RUSER=${RUSER:-$(id -un)}

printf "%b" "Remote host: "
read -r RHOST
[ -z "$RHOST" ] && { printf "%b\n" "${RED}Host required.${RC}"; exit 1; }

printf "%b" "Remote path [/]: "
read -r RPATH; RPATH=${RPATH:-/}

printf "%b" "Local mount point: "
read -r MPOINT
[ -z "$MPOINT" ] && { printf "%b\n" "${RED}Mount point required.${RC}"; exit 1; }
case "$MPOINT" in
    "~/"*) MPOINT="/home/$(id -un)/${MPOINT#~/}" ;;
    "~")   MPOINT="/home/$(id -un)" ;;
    "/"*)  ;;
    *)     printf "%b\n" "${RED}Mount point must be an absolute path (e.g. /home/$(id -un)/nas).${RC}"; exit 1 ;;
esac

SSH_DIR="/home/$(id -un)/.ssh"
FOUND_KEYS=""
for _k in "$SSH_DIR"/id_ed25519 "$SSH_DIR"/id_ecdsa "$SSH_DIR"/id_rsa "$SSH_DIR"/id_dsa; do
    [ -f "$_k" ] && FOUND_KEYS="$FOUND_KEYS $_k"
done
for _k in "$SSH_DIR"/*; do
    case "$_k" in *.pub|*known_hosts*|*config*|*authorized_keys*) continue ;; esac
    [ -f "$_k" ] || continue
    case " $FOUND_KEYS " in *" $_k "*) continue ;; esac
    head -1 "$_k" 2>/dev/null | grep -q "PRIVATE KEY" && FOUND_KEYS="$FOUND_KEYS $_k"
done

KEYFILE=""
if [ -n "$FOUND_KEYS" ]; then
    printf "%b\n" "${CYAN}Found SSH private keys:${RC}"
    _i=1
    for _k in $FOUND_KEYS; do
        printf "  %d) %s\n" "$_i" "$_k"
        _i=$((_i + 1))
    done
    printf "%b" "Select key number, or enter a custom path: "
    read -r _sel
    _i=1
    for _k in $FOUND_KEYS; do
        if [ "$_sel" = "$_i" ]; then
            KEYFILE="$_k"
            break
        fi
        _i=$((_i + 1))
    done
    [ -z "$KEYFILE" ] && KEYFILE="$_sel"
else
    printf "%b" "SSH private key path: "
    read -r KEYFILE
fi

if [ -z "$KEYFILE" ] || [ ! -f "$KEYFILE" ]; then
    printf "%b\n" "${RED}SSH key not found at $KEYFILE${RC}"
    exit 1
fi

mkdir -p "$MPOINT"
mkdir -p "$SYSTEMD_USER_DIR"

SERVICE_FILE="$SYSTEMD_USER_DIR/sshfs-${RHOST}.service"

if [ -f "$SERVICE_FILE" ]; then
    printf "%b\n" "${RED}A service for $RHOST already exists.${RC}"
    printf "%b" "Overwrite? (y/N): "
    read -r OW
    [ "$OW" != "y" ] && [ "$OW" != "Y" ] && { printf "%b\n" "${RED}Aborted.${RC}"; exit 0; }
    systemctl --user stop "sshfs-${RHOST}.service" 2>/dev/null || true
fi

cat > "$SERVICE_FILE" << EOF
[Unit]
Description=SSHFS mount $RUSER@$RHOST:$RPATH at $MPOINT
After=network-online.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=sshfs $RUSER@$RHOST:$RPATH $MPOINT -o IdentityFile=$KEYFILE,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,idmap=user
ExecStop=fusermount -u $MPOINT

[Install]
WantedBy=default.target
EOF

systemctl --user daemon-reload
systemctl --user enable --now "sshfs-${RHOST}.service" && \
    printf "%b\n" "${GREEN}Mounted and enabled at login: $RUSER@$RHOST:$RPATH -> $MPOINT${RC}" || \
    { printf "%b\n" "${RED}Mount failed. Check your SSH key and remote host.${RC}"; exit 1; }
