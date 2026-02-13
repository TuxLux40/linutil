#!/bin/sh -e
. ../common-script.sh
. ../common-service-script.sh

checkEnv

setup_sftp_server() {
    printf "%b\n" "${YELLOW}Setting up SFTP...${RC}"
    install_package sshfs openssh-server
    "$ESCALATION_TOOL" systemctl enable sshd && "$ESCALATION_TOOL" systemctl start sshd
    "$ESCALATION_TOOL" sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf 2>/dev/null || true
    printf "%b\n" "${GREEN}[OK] SSHFS + SSH ready${RC}"
}

add_fstab() {
    printf "%b" "Remote user: "; read -r U
    printf "%b" "Remote host: "; read -r H
    printf "%b" "Remote path [/volume1]: "; read -r P; P=${P:-/volume1}
    printf "%b" "Local mount [/mnt/$H]: "; read -r M; M=${M:-/mnt/$H}
    
    "$ESCALATION_TOOL" mkdir -p "$M"
    
    # Remove old entry if exists
    grep -q "$H:$P" /etc/fstab 2>/dev/null && "$ESCALATION_TOOL" sed -i "\|$H:$P|d" /etc/fstab
    
    # Add new entry (noauto - will be mounted by profile script after login)
    echo "$U@$H:$P $M fuse.sshfs noauto,reconnect,ServerAliveInterval=15,_netdev 0 0" | "$ESCALATION_TOOL" tee -a /etc/fstab >/dev/null
    
    # Create profile script to auto-mount after login
    cat << 'EOF' | "$ESCALATION_TOOL" tee /etc/profile.d/sshfs-automount.sh >/dev/null
# Auto-mount SSHFS filesystems from fstab on login
if [ -n "$SSH_AUTH_SOCK" ] || [ -n "$SSH_AGENT_PID" ]; then
    mount -a -t fuse.sshfs 2>/dev/null || true
fi
EOF
    "$ESCALATION_TOOL" chmod +x /etc/profile.d/sshfs-automount.sh
    
    printf "%b\n" "${GREEN}[OK] Added to fstab + enabled auto-mount on login${RC}"
}

list_mounts() {
    printf "%b\n" "${YELLOW}SSHFS mounts in fstab:${RC}"
    awk '$3=="fuse.sshfs" {print NR": "$0}' /etc/fstab || printf "%b\n" "${YELLOW}None${RC}"
}

remove_mount() {
    list_mounts
    printf "%b" "Line to remove: "; read -r L
    "$ESCALATION_TOOL" sed -i "${L}d" /etc/fstab
    printf "%b\n" "${GREEN}[OK] Removed${RC}"
}

test_mount() {
    printf "%b" "Mount point: "; read -r M
    printf "%b\n" "${YELLOW}Testing mount...${RC}"
    "$ESCALATION_TOOL" mount "$M" && printf "%b\n" "${GREEN}[OK] Mounted${RC}" || printf "%b\n" "${RED}[FAIL] Failed${RC}"
}

install_package() {
    for pkg in "$@"; do
        command_exists "$pkg" || "$ESCALATION_TOOL" "$PACKAGER" install -y "$pkg" >/dev/null 2>&1 || true
    done
}

while true; do
    printf "\n%b\n" "${YELLOW}=== SFTP Mount Manager ===${RC}"
    printf "%b\n" "1) Setup SFTP   2) Add mount   3) List   4) Remove   5) Test   6) Exit"
    printf "%b" "? "; read -r C
    case "$C" in
        1) setup_sftp_server ;;
        2) add_fstab ;;
        3) list_mounts ;;
        4) remove_mount ;;
        5) test_mount ;;
        6) exit 0 ;;
    esac
done
