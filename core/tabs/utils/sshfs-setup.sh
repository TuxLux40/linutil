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
        printf "%b\n" "${GREEN}$PACKAGE is already installed.${RC}"
    fi
}       

# Function to setup and configure SSHFS client with persistent mounts
setup_sshfs() {
    printf "%b\n" "${YELLOW}Setting up SSHFS client...${RC}"
    
    # Install SSHFS if not installed
    install_package sshfs
    
    # Create SSHFS mount directory if it doesn't exist
    mkdir -p ~/.sshfs
    
    printf "%b\n" "${GREEN}SSHFS client installed.${RC}"
    printf "%b\n" "${YELLOW}You can now mount remote directories persistently.${RC}"
}

# Function to add a persistent SSHFS mount to fstab
add_persistent_mount() {
    printf "%b\n" "${YELLOW}Setting up persistent SSHFS mount...${RC}"
    
    printf "%b" "Enter remote host (user@hostname or user@IP): "
    read -r REMOTE_HOST
    
    printf "%b\n" "${BLUE}Mount options:${RC}"
    printf "%b\n" "1. Mount all shared folders (like Dolphin - recommended for NAS)"
    printf "%b\n" "2. Mount specific path"
    printf "%b" "Choose (1/2): "
    read -r MOUNT_TYPE
    
    if [ "$MOUNT_TYPE" = "1" ]; then
        REMOTE_PATH="/"
        printf "%b\n" "${GREEN}Will mount all shared folders from root${RC}"
    else
        printf "%b" "Enter remote path (e.g., /volume1/data or leave empty for home): "
        read -r REMOTE_PATH
    fi
    
    printf "%b" "Enter local mount point (e.g., /mnt/nas): "
    read -r LOCAL_MOUNT

    IDENTITY_FILE=""
    SSH_DIR="$HOME/.ssh"
    if [ -d "$SSH_DIR" ]; then
        IDENTITY_CANDIDATES=$(find "$SSH_DIR" -maxdepth 5 -type f \
            \( -name "id_*" -o -name "*.key" -o -name "*.pem" -o -name "*.p8" -o -name "*.pk8" -o -name "*.ppk" \) \
            ! -name "*.pub" \
            -printf "%P\n" 2>/dev/null | sort)
    else
        IDENTITY_CANDIDATES=""
    fi

    if [ -n "$IDENTITY_CANDIDATES" ]; then
        printf "%b\n" "Available SSH identity files:"
        i=1
        for f in $IDENTITY_CANDIDATES; do
            printf "%b\n" "$i. $f"
            i=$((i + 1))
        done
        printf "%b\n" "0. Use SSH agent/config (no identityfile)"
        printf "%b\n" "M. Enter identity file path manually"
        printf "%b" "Choose identity file (number): "
        read -r ID_CHOICE

        if [ "$ID_CHOICE" = "M" ] || [ "$ID_CHOICE" = "m" ]; then
            printf "%b" "Enter identity file path: "
            read -r IDENTITY_FILE
        elif [ -n "$ID_CHOICE" ] && [ "$ID_CHOICE" != "0" ]; then
            SELECTED=$(printf "%s\n" "$IDENTITY_CANDIDATES" | sed -n "${ID_CHOICE}p")
            if [ -n "$SELECTED" ]; then
                IDENTITY_FILE="$SSH_DIR/$SELECTED"
            else
                printf "%b\n" "${YELLOW}Invalid selection. Using SSH agent/config.${RC}"
            fi
        fi
    else
        PUB_KEYS=$(find "$SSH_DIR" -maxdepth 5 -type f -name "*.pub" -printf "%P\n" 2>/dev/null | sort)
        if [ -n "$PUB_KEYS" ]; then
            printf "%b\n" "${YELLOW}Only public keys found (.pub). SSH needs the private key. Using SSH agent/config.${RC}"
        else
            printf "%b\n" "${YELLOW}No SSH identity files found in $SSH_DIR. Using SSH agent/config.${RC}"
        fi
        printf "%b\n" "M. Enter identity file path manually"
        printf "%b" "Choose (M or Enter to continue): "
        read -r ID_CHOICE
        if [ "$ID_CHOICE" = "M" ] || [ "$ID_CHOICE" = "m" ]; then
            printf "%b" "Enter identity file path: "
            read -r IDENTITY_FILE
        fi
    fi
    
    # Expand tilde if present
    LOCAL_MOUNT=$(eval echo "$LOCAL_MOUNT")

    # Expand tilde if present for identity file
    if [ -n "$IDENTITY_FILE" ]; then
        IDENTITY_FILE=$(eval echo "$IDENTITY_FILE")
    fi
    
    # Create the local mount directory
    mkdir -p "$LOCAL_MOUNT"
    
    # Build full remote path
    if [ -z "$REMOTE_PATH" ]; then
        FULL_REMOTE="$REMOTE_HOST:"
    elif [ "$REMOTE_PATH" = "/" ]; then
        FULL_REMOTE="$REMOTE_HOST:/"
    else
        FULL_REMOTE="$REMOTE_HOST:$REMOTE_PATH"
    fi
    
    # Check if mount is already in fstab
    if grep -q "$FULL_REMOTE" /etc/fstab; then
        printf "%b\n" "${YELLOW}This mount already exists in fstab.${RC}"
        return
    fi
    
    # Add to fstab with minimal FUSE-compatible options
    # user: Allow user to mount/unmount manually
    # allow_other: Allow other users to access the mount
    # reconnect: Automatically reconnect if connection drops
    # _netdev: Treat as network device (systemd waits for network)
    # x-systemd.nofail: Don't block boot if mount fails
    SSHFS_OPTIONS="user,allow_other,reconnect,_netdev,x-systemd.nofail"
    if [ -n "$IDENTITY_FILE" ]; then
        SSHFS_OPTIONS="$SSHFS_OPTIONS,identityfile=$IDENTITY_FILE"
    fi

    printf "%s %s fuse.sshfs %s 0 0\n" \
        "$FULL_REMOTE" "$LOCAL_MOUNT" "$SSHFS_OPTIONS" | \
        "$ESCALATION_TOOL" tee -a /etc/fstab > /dev/null
    
    # Reload systemd to recognize the new mount
    printf "%b\n" "${YELLOW}Reloading systemd daemon...${RC}"
    "$ESCALATION_TOOL" systemctl daemon-reload
    
    printf "%b\n" "${GREEN}Added to /etc/fstab: $FULL_REMOTE at $LOCAL_MOUNT${RC}"
    printf "%b\n" "${YELLOW}Configuration:${RC}"
    printf "%b\n" "${YELLOW}  - Mounts at boot (fast, no delays)${RC}"
    printf "%b\n" "${YELLOW}  - x-systemd.nofail: System boots even if NAS is offline${RC}"
    printf "%b\n" "${YELLOW}  - Auto-reconnect if connection drops${RC}"
    printf "%b\n" "${YELLOW}To mount now: sudo mount $LOCAL_MOUNT${RC}"
}

# Function to list and manage existing SSHFS mounts
list_mounts() {
    printf "%b\n" "${BLUE}Existing SSHFS mounts in fstab:${RC}"
    grep -E "^[^#].*fuse\.sshfs" /etc/fstab || printf "%b\n" "${YELLOW}No SSHFS mounts found.${RC}"
}

# Function to remove a SSHFS mount from fstab
remove_mount() {
    printf "%b\n" "${YELLOW}Remove SSHFS mount from fstab...${RC}"
    
    # List current mounts with line numbers
    MOUNTS=$(grep -n "^[^#].*fuse\.sshfs" /etc/fstab)
    
    if [ -z "$MOUNTS" ]; then
        printf "%b\n" "${YELLOW}No SSHFS mounts found in fstab.${RC}"
        return
    fi
    
    printf "%b\n" "${BLUE}Current SSHFS mounts:${RC}"
    echo "$MOUNTS" | nl -w2 -s'. '
    
    printf "%b" "Enter the number of the mount to remove (or 0 to cancel): "
    read -r CHOICE
    
    if [ "$CHOICE" = "0" ]; then
        printf "%b\n" "${YELLOW}Cancelled.${RC}"
        return
    fi
    
    # Get the line from fstab based on selection
    MOUNT_LINE=$(echo "$MOUNTS" | sed -n "${CHOICE}p")
    
    if [ -z "$MOUNT_LINE" ]; then
        printf "%b\n" "${RED}Invalid selection.${RC}"
        return
    fi
    
    # Extract the mount point and remote host for confirmation
    MOUNT_POINT=$(echo "$MOUNT_LINE" | awk '{print $2}')
    REMOTE=$(echo "$MOUNT_LINE" | awk '{print $1}' | cut -d: -f2-)
    
    printf "%b" "Remove mount $REMOTE at $MOUNT_POINT? (y/N): "
    read -r CONFIRM
    
    if [ "$CONFIRM" = "y" ] || [ "$CONFIRM" = "Y" ]; then
        # Unmount if currently mounted
        if mount | grep -q "$MOUNT_POINT"; then
            printf "%b\n" "${YELLOW}Unmounting $MOUNT_POINT...${RC}"
            "$ESCALATION_TOOL" umount "$MOUNT_POINT" 2>/dev/null || true
        fi
        
        # Remove from fstab
        "$ESCALATION_TOOL" sed -i "\|$REMOTE|d" /etc/fstab
        
        # Reload systemd to recognize the change
        printf "%b\n" "${YELLOW}Reloading systemd daemon...${RC}"
        "$ESCALATION_TOOL" systemctl daemon-reload
        
        printf "%b\n" "${GREEN}Mount removed from fstab.${RC}"
    else
        printf "%b\n" "${YELLOW}Cancelled.${RC}"
    fi
}

# Function to configure firewall for SSH
configure_firewall() {
    printf "%b\n" "${BLUE}Configuring firewall for SSH...${RC}"

    if command_exists ufw; then
        "$ESCALATION_TOOL" ufw allow 22/tcp
        "$ESCALATION_TOOL" ufw enable
        printf "%b\n" "${GREEN}Firewall configured to allow SSH (port 22).${RC}"
    else
        printf "%b\n" "${YELLOW}UFW is not installed. Skipping firewall configuration.${RC}"
    fi
}

# Main menu
main_menu() {
    printf "%b\n" "${BLUE}SSHFS Setup Script${RC}"
    printf "%b\n" "-----------------"
    clear

    # Display menu
    printf "%b\n" "Select an option:"
    printf "%b\n" "1. Install SSHFS client"
    printf "%b\n" "2. Add persistent SSHFS mount"
    printf "%b\n" "3. List existing SSHFS mounts"
    printf "%b\n" "4. Remove SSHFS mount from fstab"
    printf "%b\n" "5. Configure firewall for SSH"
    printf "%b\n" "6. Exit"

    printf "%b" "Enter your choice (1-6): "
    read -r CHOICE

    case "$CHOICE" in
        1)
            setup_sshfs
            ;;
        2)
            add_persistent_mount
            ;;
        3)
            list_mounts
            ;;
        4)
            remove_mount
            ;;
        5)
            configure_firewall
            ;;
        6)
            printf "%b\n" "${GREEN}Exiting.${RC}"
            exit 0
            ;;
        *)
            printf "%b\n" "${RED}Invalid choice. Please enter a number between 1 and 6.${RC}"
            exit 1
            ;;
    esac

    printf "%b\n" "${GREEN}Operation completed.${RC}"
}

checkEnv
checkEscalationTool
main_menu