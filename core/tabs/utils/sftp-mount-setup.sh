#!/bin/sh
. ../common-script.sh
. ../common-service-script.sh

checkEnv

# Ensure systemd user services are available for mount management
ensure_systemd_user() {
    if ! command_exists systemctl; then
        printf "%b\n" "${RED}systemctl not available; systemd user units are required for user mounts${RC}"
        return 1
    fi

    if ! systemctl --user show-environment >/dev/null 2>&1; then
        printf "%b\n" "${RED}systemd user session not available; log in with user services enabled${RC}"
        return 1
    fi

    return 0
}

# Ensure systemd is available for system mounts
ensure_systemd_system() {
    if ! command_exists systemctl; then
        printf "%b\n" "${RED}systemctl not available; systemd is required for system mounts${RC}"
        return 1
    fi
    return 0
}

# Convert mount path into a systemd unit-safe name
unit_name_from_path() {
    if command_exists systemd-escape; then
        systemd-escape --path "$1"
    else
        echo "$1" | sed 's|^/||; s|[[:space:]]|-|g; s|/|-|g'
    fi
}

# Check if a path is under the user's home directory
is_path_under_home() {
    case "$1" in
        "$HOME"/*) return 0 ;;
        *) return 1 ;;
    esac
}

# Resolve package name differences across distros
resolve_package_name() {
    case "$1" in
        openssh-server)
            case "$PACKAGER" in
                pacman | apk | xbps-install | zypper)
                    echo "openssh"
                    ;;
                *)
                    echo "openssh-server"
                    ;;
            esac
            ;;
        *)
            echo "$1"
            ;;
    esac
}

# Install and enable SSHFS and SSH server for remote mounting capabilities
# Sets up the required packages and services needed for SFTP mount functionality
setup_sftp_server() {
    printf "%b\n" "${YELLOW}Setting up SFTP...${RC}"
    printf "%b\n" "${YELLOW}Installing packages...${RC}"
    install_package sshfs sshfs
    install_package openssh-server sshd
    printf "%b\n" "${YELLOW}Enabling SSH server...${RC}"
    if ! enable_ssh_service; then
        printf "%b\n" "${RED}[FAIL] Could not enable SSH service${RC}"
        return 1
    fi
    printf "%b\n" "${YELLOW}Configuring FUSE...${RC}"
    "$ESCALATION_TOOL" sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf 2>/dev/null || true
    printf "%b\n" "${GREEN}[OK] SSHFS + SSH ready${RC}"
}

# Enable and start the SSH service using the detected init system
enable_ssh_service() {
    for svc in sshd ssh; do
        if isServiceActive "$svc" >/dev/null 2>&1; then
            return 0
        fi
        if startAndEnableService "$svc" >/dev/null 2>&1; then
            return 0
        fi
    done

    return 1
}

# Create a new systemd mount for SSHFS
# Prompts for remote user, host, path, and local mount point
# Creates systemd .mount and .automount unit files
# Auto-enables and starts the automount unit for convenient on-demand mounting
add_systemd_mount() {
    printf "%b" "${YELLOW}Remote user: ${RC}"
    read -r U
    printf "%b" "${YELLOW}Remote host: ${RC}"
    read -r H
    printf "%b" "${YELLOW}SSH port [22]: ${RC}"
    read -r SSH_PORT
    SSH_PORT=${SSH_PORT:-22}
    printf "%b" "${YELLOW}Remote path [/volume1]: ${RC}"
    read -r P
    P=${P:-/volume1}
    printf "%b" "${YELLOW}Local mount [~/mnt/$H]: ${RC}"
    read -r M
    M=${M:-$HOME/mnt/$H}

    printf "%b" "${YELLOW}SSH identity file (blank for default agent keys): ${RC}"
    read -r ID_FILE

    printf "%b" "${YELLOW}Enable automount? [Y/n]: ${RC}"
    read -r USE_AUTOMOUNT
    if [ -n "$USE_AUTOMOUNT" ] && [ "$USE_AUTOMOUNT" = "n" ]; then
        USE_AUTOMOUNT="no"
    else
        USE_AUTOMOUNT="yes"
    fi

    MODE="system"
    printf "%b" "${YELLOW}Use system-wide mount? [Y/n]: ${RC}"
    read -r USE_SYSTEM
    if [ -n "$USE_SYSTEM" ] && [ "$USE_SYSTEM" != "y" ]; then
        MODE="user"
    fi

    if [ "$MODE" = "system" ]; then
        ensure_systemd_system || return
    else
        ensure_systemd_user || return
    fi

    if [ "$MODE" = "user" ] && ! is_path_under_home "$M"; then
        printf "%b\n" "${YELLOW}User mounts outside $HOME can fail. Using $HOME/mnt/$H instead.${RC}"
        M="$HOME/mnt/$H"
    fi

    # Create mount directory with appropriate privileges
    if [ "$MODE" = "system" ]; then
        if ! "$ESCALATION_TOOL" mkdir -p "$M"; then
            printf "%b\n" "${RED}[FAIL] Could not create mount directory at $M${RC}"
            return 1
        fi
    else
        if ! mkdir -p "$M"; then
            printf "%b\n" "${RED}[FAIL] Could not create mount directory at $M${RC}"
            return 1
        fi
    fi

    # Convert mount path to systemd unit name (e.g., /home/user/mnt/server -> home-user-mnt-server)
    UNIT_NAME=$(unit_name_from_path "$M")
    if [ "$MODE" = "system" ]; then
        MOUNT_UNIT="/etc/systemd/system/${UNIT_NAME}.mount"
        AUTOMOUNT_UNIT="/etc/systemd/system/${UNIT_NAME}.automount"
    else
        MOUNT_UNIT="$HOME/.config/systemd/user/${UNIT_NAME}.mount"
        AUTOMOUNT_UNIT="$HOME/.config/systemd/user/${UNIT_NAME}.automount"
        mkdir -p "$HOME/.config/systemd/user"
    fi

    SSHFS_OPTIONS="allow_other,reconnect,ServerAliveInterval=15,_netdev"
    if [ -n "$SSH_PORT" ] && [ "$SSH_PORT" != "22" ]; then
        SSHFS_OPTIONS="${SSHFS_OPTIONS},port=${SSH_PORT}"
    fi
    if [ -n "$ID_FILE" ]; then
        SSHFS_OPTIONS="${SSHFS_OPTIONS},IdentityFile=${ID_FILE},UserKnownHostsFile=${HOME}/.ssh/known_hosts,StrictHostKeyChecking=accept-new"
    fi

    MOUNT_UNIT_CONTENT="[Unit]
Description=SSHFS mount for $U@$H:$P
After=network-online.target
Wants=network-online.target

[Mount]
What=$U@$H:$P
Where=$M
Type=fuse.sshfs
Options=$SSHFS_OPTIONS

[Install]
WantedBy=default.target
"

    AUTOMOUNT_UNIT_CONTENT="[Unit]
Description=Auto-mount SSHFS for $U@$H:$P

[Automount]
Where=$M

[Install]
WantedBy=default.target
"

    # Create mount unit
    if [ "$MODE" = "system" ]; then
        printf "%b" "$MOUNT_UNIT_CONTENT" | "$ESCALATION_TOOL" tee "$MOUNT_UNIT" >/dev/null
    else
        printf "%b" "$MOUNT_UNIT_CONTENT" > "$MOUNT_UNIT"
    fi

    # Create automount unit (optional)
    if [ "$USE_AUTOMOUNT" = "yes" ]; then
        if [ "$MODE" = "system" ]; then
            printf "%b" "$AUTOMOUNT_UNIT_CONTENT" | "$ESCALATION_TOOL" tee "$AUTOMOUNT_UNIT" >/dev/null
        else
            printf "%b" "$AUTOMOUNT_UNIT_CONTENT" > "$AUTOMOUNT_UNIT"
        fi
    fi

    if [ "$MODE" = "system" ]; then
        "$ESCALATION_TOOL" systemctl daemon-reload
        if [ "$USE_AUTOMOUNT" = "yes" ]; then
            if "$ESCALATION_TOOL" systemctl enable --now "$UNIT_NAME.automount" 2>&1; then
                printf "%b\n" "${GREEN}[OK] Created systemd system automount for $M${RC}"
                return 0
            fi
            printf "%b\n" "${RED}[FAIL] Could not enable automount unit. Falling back to direct mount...${RC}"
        fi

        if "$ESCALATION_TOOL" systemctl enable --now "$UNIT_NAME.mount" 2>&1; then
            printf "%b\n" "${GREEN}[OK] Created systemd system mount for $M${RC}"
        else
            printf "%b\n" "${RED}[FAIL] Could not enable mount unit. Check journalctl -xe for details${RC}"
            printf "%b\n" "${YELLOW}Mount unit files created at:${RC}"
            printf "%b\n" "  $MOUNT_UNIT"
            if [ "$USE_AUTOMOUNT" = "yes" ]; then
                printf "%b\n" "  $AUTOMOUNT_UNIT"
            fi
        fi
    else
        systemctl --user daemon-reload
        if [ "$USE_AUTOMOUNT" = "yes" ]; then
            if systemctl --user enable --now "$UNIT_NAME.automount" 2>&1; then
                printf "%b\n" "${GREEN}[OK] Created systemd user automount for $M${RC}"
                return 0
            fi
            printf "%b\n" "${RED}[FAIL] Could not enable automount unit. Falling back to direct mount...${RC}"
        fi

        if systemctl --user enable --now "$UNIT_NAME.mount" 2>&1; then
            printf "%b\n" "${GREEN}[OK] Created systemd user mount for $M${RC}"
        else
            printf "%b\n" "${RED}[FAIL] Could not enable mount unit. Check journalctl -xe for details${RC}"
            printf "%b\n" "${YELLOW}Mount unit files created at:${RC}"
            printf "%b\n" "  $MOUNT_UNIT"
            if [ "$USE_AUTOMOUNT" = "yes" ]; then
                printf "%b\n" "  $AUTOMOUNT_UNIT"
            fi
        fi
    fi
}

# Display all configured SSHFS mounts managed by systemd
# Shows both enabled automount units and currently active mounts
list_mounts() {
    printf "%b\n" "${YELLOW}SSHFS mounts (systemd units):${RC}"
    printf "%b\n" "User units:"
    if ensure_systemd_user; then
        if [ -d "$HOME/.config/systemd/user" ] && ls "$HOME/.config/systemd/user"/*.automount >/dev/null 2>&1; then
            for unit in "$HOME/.config/systemd/user"/*.automount; do
                UNIT_BASE=$(basename "$unit")
                STATE=$(systemctl --user is-enabled "$UNIT_BASE" 2>/dev/null || printf "%s" "unknown")
                printf "%b\n" "  $UNIT_BASE ($STATE)"
            done
        else
            printf "%b\n" "${YELLOW}None${RC}"
        fi
    else
        printf "%b\n" "${YELLOW}Unavailable${RC}"
    fi

    printf "%b\n" "System units:"
    if ensure_systemd_system; then
        if [ -d "/etc/systemd/system" ] && ls "/etc/systemd/system"/*.automount >/dev/null 2>&1; then
            for unit in /etc/systemd/system/*.automount; do
                UNIT_BASE=$(basename "$unit")
                STATE=$(systemctl is-enabled "$UNIT_BASE" 2>/dev/null || printf "%s" "unknown")
                printf "%b\n" "  $UNIT_BASE ($STATE)"
            done
        else
            printf "%b\n" "${YELLOW}None${RC}"
        fi
    else
        printf "%b\n" "${YELLOW}Unavailable${RC}"
    fi

    printf "%b\n" "Active mounts:"
    if [ -r /proc/mounts ]; then
        if grep -q "fuse.sshfs" /proc/mounts; then
            awk '$3 == "fuse.sshfs" {print "  " $2}' /proc/mounts
        else
            printf "%b\n" "${YELLOW}None${RC}"
        fi
    else
        printf "%b\n" "${YELLOW}None${RC}"
    fi
}

# Remove a configured SSHFS mount
# Lists available systemd units and removes the selected mount
# Disables and stops the automount/mount units, then deletes the unit files
remove_mount() {
    printf "%b\n" "${YELLOW}Remove system or user unit?${RC}"
    printf "%b\n" "1) System   2) User   3) Cancel"
    printf "%b" "? "; read -r SCOPE

    case "$SCOPE" in
        1)
            ensure_systemd_system || return
            printf "%b\n" "${YELLOW}System SSHFS units:${RC}"
            ls "/etc/systemd/system"/*-*.automount 2>/dev/null | nl || {
                printf "%b\n" "${YELLOW}None${RC}"
                return
            }
            printf "%b" "Unit number to remove: "; read -r L
            UNIT=$(ls "/etc/systemd/system"/*-*.automount 2>/dev/null | sed -n "${L}p")
            if [ -n "$UNIT" ]; then
                UNIT_BASE=$(basename "$UNIT" .automount)
                "$ESCALATION_TOOL" systemctl disable --now "$UNIT_BASE.automount" 2>/dev/null || true
                "$ESCALATION_TOOL" systemctl disable --now "$UNIT_BASE.mount" 2>/dev/null || true
                "$ESCALATION_TOOL" rm -f "/etc/systemd/system/${UNIT_BASE}.automount"
                "$ESCALATION_TOOL" rm -f "/etc/systemd/system/${UNIT_BASE}.mount"
                "$ESCALATION_TOOL" systemctl daemon-reload
                printf "%b\n" "${GREEN}[OK] Removed${RC}"
            else
                printf "%b\n" "${RED}[FAIL] Invalid selection${RC}"
            fi
            ;;
        2)
            ensure_systemd_user || return
            printf "%b\n" "${YELLOW}User SSHFS units:${RC}"
            ls "$HOME/.config/systemd/user"/*-*.automount 2>/dev/null | nl || {
                printf "%b\n" "${YELLOW}None${RC}"
                return
            }
            printf "%b" "Unit number to remove: "; read -r L
            UNIT=$(ls "$HOME/.config/systemd/user"/*-*.automount 2>/dev/null | sed -n "${L}p")
            if [ -n "$UNIT" ]; then
                UNIT_BASE=$(basename "$UNIT" .automount)
                systemctl --user disable --now "$UNIT_BASE.automount" 2>/dev/null || true
                systemctl --user disable --now "$UNIT_BASE.mount" 2>/dev/null || true
                rm -f "$HOME/.config/systemd/user/${UNIT_BASE}.automount"
                rm -f "$HOME/.config/systemd/user/${UNIT_BASE}.mount"
                systemctl --user daemon-reload
                printf "%b\n" "${GREEN}[OK] Removed${RC}"
            else
                printf "%b\n" "${RED}[FAIL] Invalid selection${RC}"
            fi
            ;;
        *)
            return
            ;;
    esac
}

# Test if a mount point is accessible
# Attempts to access the mount directory to trigger automount if needed
# Optionally displays systemd unit status for troubleshooting on failure
test_mount() {
    printf "%b\n" "${YELLOW}Available mount points:${RC}"
    
    # Show system mounts
    if [ -d "/etc/systemd/system" ] && ls "/etc/systemd/system"/*.mount >/dev/null 2>&1; then
        for unit in /etc/systemd/system/*.mount; do
            if [ -f "$unit" ]; then
                WHERE=$(grep "^Where=" "$unit" 2>/dev/null | cut -d'=' -f2)
                [ -n "$WHERE" ] && printf "%b\n" "  $WHERE (system)"
            fi
        done
    fi
    
    # Show user mounts
    if [ -d "$HOME/.config/systemd/user" ] && ls "$HOME/.config/systemd/user"/*.mount >/dev/null 2>&1; then
        for unit in "$HOME/.config/systemd/user"/*.mount; do
            if [ -f "$unit" ]; then
                WHERE=$(grep "^Where=" "$unit" 2>/dev/null | cut -d'=' -f2)
                [ -n "$WHERE" ] && printf "%b\n" "  $WHERE (user)"
            fi
        done
    fi
    
    printf "%b" "${YELLOW}Mount point (absolute path): ${RC}"
    read -r M
    
    # Validate input is an absolute path
    case "$M" in
        /*)
            # Valid absolute path
            ;;
        *)
            printf "%b\n" "${RED}[FAIL] '$M' is not an absolute path (must start with /)${RC}"
            return 1
            ;;
    esac
    
    printf "%b\n" "${YELLOW}Testing mount...${RC}"

    # Try to access the mount point to trigger automount
    if ls "$M" >/dev/null 2>&1; then
        printf "%b\n" "${GREEN}[OK] Mount accessible${RC}"
        printf "%b\n" "Contents:"
        ls -lh "$M" 2>/dev/null | head -10 || printf "%b\n" "${YELLOW}(empty or no permission)${RC}"
    else
        printf "%b\n" "${RED}[FAIL] Mount not accessible${RC}"
        printf "%b" "View systemd status? (y/n): "; read -r VIEWSTATUS
        if [ "$VIEWSTATUS" = "y" ]; then
            UNIT_NAME=$(unit_name_from_path "$M")
            if [ -f "/etc/systemd/system/${UNIT_NAME}.mount" ]; then
                "$ESCALATION_TOOL" systemctl status "${UNIT_NAME}.mount" --no-pager || true
            else
                if ensure_systemd_user; then
                    systemctl --user status "${UNIT_NAME}.mount" --no-pager || true
                fi
            fi
        fi
    fi
}

# Install packages if not already present
# Accepts package name and binary name
# Uses the system package manager and escalation tool for installation
install_package() {
    PKG="$1"
    BIN="$2"
    RESOLVED_PKG=$(resolve_package_name "$PKG")

    if command_exists "$BIN"; then
        printf "%b\n" "$BIN already installed"
        return 0
    fi

    printf "%b" "${YELLOW}Installing $RESOLVED_PKG...${RC} "
    case "$PACKAGER" in
        pacman)
            if "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm "$RESOLVED_PKG" >/dev/null 2>&1; then
                printf "%b\n" "${GREEN}[OK]${RC}"
            else
                printf "%b\n" "${RED}[FAIL]${RC}"
            fi
            ;;
        apk)
            if "$ESCALATION_TOOL" "$PACKAGER" add "$RESOLVED_PKG" >/dev/null 2>&1; then
                printf "%b\n" "${GREEN}[OK]${RC}"
            else
                printf "%b\n" "${RED}[FAIL]${RC}"
            fi
            ;;
        xbps-install)
            if "$ESCALATION_TOOL" "$PACKAGER" -Sy "$RESOLVED_PKG" >/dev/null 2>&1; then
                printf "%b\n" "${GREEN}[OK]${RC}"
            else
                printf "%b\n" "${RED}[FAIL]${RC}"
            fi
            ;;
        *)
            if "$ESCALATION_TOOL" "$PACKAGER" install -y "$RESOLVED_PKG" >/dev/null 2>&1; then
                printf "%b\n" "${GREEN}[OK]${RC}"
            else
                printf "%b\n" "${RED}[FAIL]${RC}"
            fi
            ;;
    esac
}

# Automatically setup SFTP on script start
setup_sftp_server

while true; do
    printf "\n%b\n" "${YELLOW}=== SFTP Mount Manager (systemd) ===${RC}"
    printf "%b\n" "1) Add mount   2) List   3) Remove   4) Test   5) Exit"
    printf "%b" "? "; read -r C
    case "$C" in
        1) add_systemd_mount ;;
        2) list_mounts ;;
        3) remove_mount ;;
        4) test_mount ;;
        5) exit 0 ;;
    esac
done
