#!/bin/sh -e

# Load common script functions
. ../common-script.sh  
. ../common-service-script.sh

# Function to install packages based on the package manager
install_package() {
    PACKAGE=$1
    if ! command_exists "$PACKAGE"; then
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm "$PACKAGE"
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add "$PACKAGE"
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy "$PACKAGE"
                ;;
            *)
                "$ESCALATION_TOOL" "$PACKAGER" install -y "$PACKAGE"
                ;;
        esac
    else
        echo "$PACKAGE is already installed."
    fi
}

# Function to setup and configure SFTP server (SSH)
setup_sftp_server() {
    printf "%b\n" "${YELLOW}Setting up SFTP Server...${RC}"

    # Detect package manager and install appropriate SSH package
    case "$PACKAGER" in
    apt-get|nala)
        install_package openssh-server
        SSH_SERVICE="ssh"
        ;;
    pacman)
        install_package openssh
        SSH_SERVICE="sshd"
        ;;
    apk)
        install_package openssh
        SSH_SERVICE="sshd"
        ;;
    xbps-install)
        install_package openssh
        SSH_SERVICE="sshd"
        ;;
    *)
        install_package openssh-server
        SSH_SERVICE="sshd"
        ;;
    esac

    startAndEnableService "$SSH_SERVICE"

    LOCAL_IP=$(ip -4 addr show | awk '/inet / {print $2}' | tail -n 1)

    printf "%b\n" "${GREEN}Your local IP address is: $LOCAL_IP${RC}"

    # Configure SFTP in SSH config if not already configured
    SSH_CONFIG="/etc/ssh/sshd_config"
    SFTP_CONFIGURED=$(grep -c "Subsystem sftp" "$SSH_CONFIG" || true)

    if [ "$SFTP_CONFIGURED" -eq 0 ]; then
        printf "%b\n" "${YELLOW}Configuring SFTP subsystem in SSH...${RC}"
        "$ESCALATION_TOOL" tee -a "$SSH_CONFIG" > /dev/null <<EOL

# SFTP Subsystem
Subsystem sftp	/usr/lib/openssh/sftp-server
EOL
        "$ESCALATION_TOOL" systemctl restart "$SSH_SERVICE"
    else
        printf "%b\n" "${GREEN}SFTP subsystem already configured.${RC}"
    fi

    if isServiceActive "$SSH_SERVICE"; then
        printf "%b\n" "${GREEN}SFTP Server (SSH) is up and running on $LOCAL_IP:22${RC}"
    else
        printf "%b\n" "${RED}Failed to start SFTP Server.${RC}"
    fi
}

# Function to setup SFTP client (SSH FS)
setup_sftp_client() {
    printf "%b\n" "${YELLOW}Setting up SFTP Client (SSH FS)...${RC}"

    # Install sshfs for mounting remote filesystems
    install_package sshfs

    # Install openssh-client if not already installed
    case "$PACKAGER" in
    apt-get|nala)
        install_package openssh-client
        ;;
    *)
        # Most distros include ssh as part of openssh-clients or openssh package
        install_package openssh
        ;;
    esac

    printf "%b\n" "${GREEN}SFTP Client tools installed.${RC}"
    printf "%b\n" "${YELLOW}To mount a remote SFTP location, use:${RC}"
    printf "%b\n" "${BLUE}mkdir -p /mnt/remote${RC}"
    printf "%b\n" "${BLUE}sshfs username@remote-host:/path/to/folder /mnt/remote${RC}"
    printf "%b\n" "${YELLOW}To unmount:${RC}"
    printf "%b\n" "${BLUE}fusermount -u /mnt/remote${RC}"
}

# Function to create and mount SFTP point
create_sftp_mount() {
    printf "%b\n" "${YELLOW}Creating SFTP Mount Point...${RC}"

    # Get mount details from user
    printf "%b" "Enter remote username: "
    read -r SSH_USER

    printf "%b" "Enter remote host (IP or hostname): "
    read -r SSH_HOST

    printf "%b" "Enter remote path to mount (default: /home): "
    read -r REMOTE_PATH
    REMOTE_PATH=${REMOTE_PATH:-/home}

    printf "%b" "Enter local mount point (default: /mnt/sftp_$SSH_HOST): "
    read -r LOCAL_MOUNT
    LOCAL_MOUNT=${LOCAL_MOUNT:-/mnt/sftp_$SSH_HOST}

    # Create local mount directory
    printf "%b\n" "${YELLOW}Creating mount directory at $LOCAL_MOUNT...${RC}"
    "$ESCALATION_TOOL" mkdir -p "$LOCAL_MOUNT"

    # Test SSH connection first
    printf "%b\n" "${YELLOW}Testing SSH connection to $SSH_USER@$SSH_HOST...${RC}"
    if ssh -o ConnectTimeout=5 "$SSH_USER@$SSH_HOST" exit 2>/dev/null; then
        printf "%b\n" "${GREEN}SSH connection successful.${RC}"
    else
        printf "%b\n" "${RED}Failed to connect to $SSH_USER@$SSH_HOST. Please check credentials and connectivity.${RC}"
        return 1
    fi

    # Mount SFTP
    printf "%b\n" "${YELLOW}Mounting SFTP filesystem...${RC}"
    if sshfs "$SSH_USER@$SSH_HOST:$REMOTE_PATH" "$LOCAL_MOUNT" -o reconnect,ServerAliveInterval=15; then
        printf "%b\n" "${GREEN}SFTP mount successful at $LOCAL_MOUNT${RC}"
        printf "%b\n" "${YELLOW}To unmount, run: fusermount -u $LOCAL_MOUNT${RC}"
    else
        printf "%b\n" "${RED}Failed to mount SFTP filesystem.${RC}"
        return 1
    fi
}

# Function to build persistent mount entry
create_persistent_mount() {
    printf "%b\n" "${YELLOW}Creating Persistent SFTP Mount (fstab)...${RC}"

    # Get mount details from user
    printf "%b" "Enter remote username: "
    read -r SSH_USER

    printf "%b" "Enter remote host (IP or hostname): "
    read -r SSH_HOST

    printf "%b" "Enter remote path to mount (default: /home): "
    read -r REMOTE_PATH
    REMOTE_PATH=${REMOTE_PATH:-/home}

    printf "%b" "Enter local mount point (default: /mnt/sftp_$SSH_HOST): "
    read -r LOCAL_MOUNT
    LOCAL_MOUNT=${LOCAL_MOUNT:-/mnt/sftp_$SSH_HOST}

    # Create mount point
    printf "%b\n" "${YELLOW}Creating mount directory at $LOCAL_MOUNT...${RC}"
    "$ESCALATION_TOOL" mkdir -p "$LOCAL_MOUNT"

    # Test SSH connection first
    printf "%b\n" "${YELLOW}Testing SSH connection to $SSH_USER@$SSH_HOST...${RC}"
    if ssh -o ConnectTimeout=5 "$SSH_USER@$SSH_HOST" exit 2>/dev/null; then
        printf "%b\n" "${GREEN}SSH connection successful.${RC}"
    else
        printf "%b\n" "${RED}Failed to connect to $SSH_USER@$SSH_HOST. Please check credentials and connectivity.${RC}"
        return 1
    fi

    # Configure FUSE if needed
    if [ -f /etc/fuse.conf ]; then
        FUSE_CONFIGURED=$(grep -c "user_allow_other" /etc/fuse.conf || true)
        if [ "$FUSE_CONFIGURED" -eq 0 ]; then
            printf "%b\n" "${YELLOW}Configuring FUSE for user_allow_other...${RC}"
            "$ESCALATION_TOOL" sed -i 's/#user_allow_other/user_allow_other/' /etc/fuse.conf
        fi
    fi

    # Get SSH key path
    printf "%b" "SSH key path (default: ~/.ssh/id_rsa): "
    read -r SSH_KEY
    SSH_KEY=${SSH_KEY:-~/.ssh/id_rsa}

    # Systemd automount options (mount after login/on access and keep mounted)
    printf "%b" "Enable systemd automount after login (Y/n): "
    read -r USE_AUTOMOUNT
    case "$USE_AUTOMOUNT" in
        n|N)
            SYSTEMD_AUTOMOUNT_OPTS=""
            ;;
        *)
            SYSTEMD_AUTOMOUNT_OPTS="x-systemd.automount,x-systemd.idle-timeout=0,x-systemd.device-timeout=30s,x-systemd.mount-timeout=30s,x-systemd.requires=network-online.target,x-systemd.after=network-online.target"
            ;;
    esac

    # Escape the mount point for fstab
    FSTAB_MOUNT=$(echo "$LOCAL_MOUNT" | sed 's/ /\\040/g')

    # Build fstab entry
    FSTAB_ENTRY="$SSH_USER@$SSH_HOST:$REMOTE_PATH	$FSTAB_MOUNT	fuse.sshfs	defaults,IdentityFile=$SSH_KEY,reconnect,ServerAliveInterval=15,ServerAliveCountMax=3,_netdev,nofail$([ -n "$SYSTEMD_AUTOMOUNT_OPTS" ] && printf ",%s" "$SYSTEMD_AUTOMOUNT_OPTS")	0	0"

    # Check if already in fstab
    if grep -q "$SSH_HOST:$REMOTE_PATH" /etc/fstab; then
        printf "%b\n" "${YELLOW}An entry for this mount already exists in fstab.${RC}"
        printf "%b" "Overwrite existing entry? (y/N): "
        read -r OVERWRITE
        if [ "$OVERWRITE" = "y" ] || [ "$OVERWRITE" = "Y" ]; then
            "$ESCALATION_TOOL" sed -i "/$SSH_HOST:$REMOTE_PATH/d" /etc/fstab
        else
            printf "%b\n" "${YELLOW}Skipping fstab entry.${RC}"
            return 0
        fi
    fi

    # Add to fstab
    printf "%b\n" "${YELLOW}Adding entry to /etc/fstab...${RC}"
    echo "$FSTAB_ENTRY" | "$ESCALATION_TOOL" tee -a /etc/fstab > /dev/null

    # Test the mount
    printf "%b\n" "${YELLOW}Testing mount...${RC}"
    if "$ESCALATION_TOOL" mount "$LOCAL_MOUNT"; then
        printf "%b\n" "${GREEN}SFTP mount successful!${RC}"
        printf "%b\n" "${GREEN}Persistent SFTP mount added to /etc/fstab${RC}"
        printf "%b\n" "${YELLOW}To unmount: sudo umount $LOCAL_MOUNT${RC}"
        printf "%b\n" "${YELLOW}To mount all fstab entries: sudo mount -a${RC}"
    else
        printf "%b\n" "${RED}Failed to mount. Check SSH key and remote path.${RC}"
        printf "%b\n" "${YELLOW}Removing failed entry from fstab...${RC}"
        "$ESCALATION_TOOL" sed -i "/$SSH_HOST:$REMOTE_PATH/d" /etc/fstab
        return 1
    fi
}

# Function to remove persistent mount entry
remove_persistent_mount() {
    printf "%b\n" "${YELLOW}Removing Persistent SFTP Mount (fstab)...${RC}"

    printf "%b" "Enter remote host (IP or hostname): "
    read -r SSH_HOST

    printf "%b" "Enter remote path to remove (default: /home): "
    read -r REMOTE_PATH
    REMOTE_PATH=${REMOTE_PATH:-/home}

    MATCHES=$(grep -n "${SSH_HOST}:${REMOTE_PATH}" /etc/fstab || true)
    if [ -z "$MATCHES" ]; then
        printf "%b\n" "${YELLOW}No matching fstab entries found for $SSH_HOST:$REMOTE_PATH.${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Matching fstab entries:${RC}"
    printf "%b\n" "$MATCHES"

    printf "%b" "Proceed to remove these entries? (y/N): "
    read -r CONFIRM
    if [ "$CONFIRM" != "y" ] && [ "$CONFIRM" != "Y" ]; then
        printf "%b\n" "${YELLOW}Skipping removal.${RC}"
        return 0
    fi

    printf "%b\n" "${YELLOW}Attempting to unmount any matching mounts...${RC}"
    MOUNT_POINTS=$(printf "%s\n" "$MATCHES" | awk '{print $2}')
    for MP in $MOUNT_POINTS; do
        if mountpoint -q "$MP"; then
            "$ESCALATION_TOOL" umount "$MP" || true
        fi
    done

    printf "%b\n" "${YELLOW}Removing entries from /etc/fstab...${RC}"
    "$ESCALATION_TOOL" sed -i "/${SSH_HOST}:${REMOTE_PATH}/d" /etc/fstab
    printf "%b\n" "${GREEN}Removed persistent mount entries for $SSH_HOST:$REMOTE_PATH.${RC}"
}

# Function to configure firewall (optional)
configure_firewall() {
    printf "%b\n" "${BLUE}Configuring firewall for SFTP...${RC}"

    if command_exists ufw; then
        "$ESCALATION_TOOL" ufw allow 22/tcp
        "$ESCALATION_TOOL" ufw enable
        printf "%b\n" "${GREEN}Firewall configured to allow SSH/SFTP (port 22).${RC}"
    else
        printf "%b\n" "${YELLOW}UFW is not installed. Skipping firewall configuration.${RC}"
    fi
}

setup_sftp_mount(){
    printf "%b\n" "SFTP Mount Setup Script"
    printf "%b\n" "-----------------------"
    clear

    # Display menu
    printf "%b\n" "Select an option:"
    printf "%b\n" "1. Setup SFTP Server (SSH)"
    printf "%b\n" "2. Setup SFTP Client"
    printf "%b\n" "3. Create SFTP Mount"
    printf "%b\n" "4. Create Persistent SFTP Mount (fstab + systemd automount)"
    printf "%b\n" "5. Remove Persistent SFTP Mount (fstab)"
    printf "%b\n" "6. Configure Firewall"
    printf "%b\n" "7. Setup All"
    printf "%b\n" "8. Exit"

    printf "%b" "Enter your choice (1-8): "
    read -r CHOICE

    case "$CHOICE" in
        1)
            setup_sftp_server
            ;;
        2)
            setup_sftp_client
            ;;
        3)
            install_package sshfs
            create_sftp_mount
            ;;
        4)
            install_package sshfs
            create_persistent_mount
            ;;
        5)
            remove_persistent_mount
            ;;
        6)
            configure_firewall
            ;;
        7)
            setup_sftp_server
            setup_sftp_client
            configure_firewall
            printf "%b\n" "${YELLOW}Now you can create SFTP mounts using option 3 or 4.${RC}"
            ;;
        8)
            printf "%b\n" "${GREEN}Exiting.${RC}"
            exit 0
            ;;
        *)
            printf "%b\n" "${RED}Invalid choice. Please enter a number between 1 and 8.${RC}"
            exit 1
            ;;
    esac

    printf "%b\n" "${GREEN}Setup completed.${RC}"
}

checkEnv
checkEscalationTool
setup_sftp_mount
