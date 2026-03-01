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

install_sshfs

printf "%b\n" "${YELLOW}--- SSHFS Mount Setup ---${RC}"
printf "%b" "Remote user [$(id -un)]: "
read -r RUSER; RUSER=${RUSER:-$(id -un)}
printf "%b" "Remote host: "
read -r RHOST
[ -z "$RHOST" ] && { printf "%b\n" "${RED}Host required${RC}"; exit 1; }
printf "%b" "SSH port [22]: "
read -r RPORT; RPORT=${RPORT:-22}
printf "%b" "Remote path [/]: "
read -r RPATH; RPATH=${RPATH:-/}
printf "%b" "Local mount point [/mnt/$RHOST]: "
read -r MPOINT; MPOINT=${MPOINT:-/mnt/$RHOST}

sudo sshfs "$RUSER@$RHOST:$RPATH" "$MPOINT" -p "$RPORT" -o idmap=user -o allow_other
