#!/bin/sh -e

. ../common-script.sh

DRY_RUN=${DRY_RUN:-0}

installAudit() {
    if ! command_exists auditctl; then
        printf "%b\n" "${YELLOW}Installing auditd...${RC}"
        case "$PACKAGER" in
            pacman)
                "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm audit
                ;;
            apt)
                "$ESCALATION_TOOL" "$PACKAGER" install -y auditd audispd-plugins
                ;;
            dnf)
                "$ESCALATION_TOOL" "$PACKAGER" install -y audit
                ;;
            apk)
                "$ESCALATION_TOOL" "$PACKAGER" add audit
                ;;
            xbps-install)
                "$ESCALATION_TOOL" "$PACKAGER" -Sy audit
                ;;
            *)
                printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
                return 1
                ;;
        esac
        printf "%b\n" "${GREEN}auditd installed${RC}"
    else
        printf "%b\n" "${GREEN}auditd is already installed${RC}"
    fi
}

deployAuditRules() {
    RULES_FILE="/etc/audit/rules.d/99-hardening.rules"
    
    # Check if rules file already exists with matching content
    if [ -f "$RULES_FILE" ]; then
        if grep -q "file deletions, privilege escalation" "$RULES_FILE" 2>/dev/null; then
            printf "%b\n" "${GREEN}Audit rules already deployed${RC}"
            return 0
        fi
    fi
    
    printf "%b\n" "${YELLOW}Deploying audit rules to $RULES_FILE...${RC}"
    
    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would create $RULES_FILE with the following rules:${RC}"
        cat << 'EOF'
# Audit rules for comprehensive system security monitoring
# - File deletions, privilege escalation, sensitive file changes
# - Kernel module operations, network configuration
# - SSH configuration, system call monitoring

# Clear existing rules
-D

# Buffer Size
-b 8192

# Failure Mode (1 = printk to syslog)
-f 1

# System Call Monitoring
# Program execution
-a always,exit -F arch=b64 -S execve -F key=exec
# File access with permission denied
-a always,exit -F arch=b64 -S open,openat,openat2 -F exit=-EACCES -F key=access
-a always,exit -F arch=b64 -S open,openat,openat2 -F exit=-EPERM -F key=access

# File Deletions and Renames
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F key=delete

# Privilege Escalation
-w /usr/bin/sudo -p x -k priv_esc
-w /bin/su -p x -k priv_esc

# Sensitive File Modifications
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# SSH Security
-w /etc/ssh/sshd_config -p wa -k sshd_config_changes
-w /root/.ssh -p wa -k root_ssh_key_changes

# Kernel Module Operations
-a always,exit -F arch=b64 -S init_module,delete_module -F key=modules
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules

# Network Configuration
-w /etc/hosts -p wa -k network_modifications
-w /etc/hostname -p wa -k network_modifications
-w /etc/sysctl.conf -p wa -k network_modifications
-w /etc/sysctl.d/ -p wa -k network_modifications

# Network Connection Monitoring
-a always,exit -F arch=b64 -S socket -S connect -F a1!=2 -F key=network_connections

# Make configuration immutable
-e 2
EOF
        return 0
    fi
    
    "$ESCALATION_TOOL" mkdir -p /etc/audit/rules.d
    
    "$ESCALATION_TOOL" tee "$RULES_FILE" > /dev/null << 'EOF'
# Audit rules for comprehensive system security monitoring
# - File deletions, privilege escalation, sensitive file changes
# - Kernel module operations, network configuration
# - SSH configuration, system call monitoring

# Clear existing rules
-D

# Buffer Size
-b 8192

# Failure Mode (1 = printk to syslog)
-f 1

# System Call Monitoring
# Program execution
-a always,exit -F arch=b64 -S execve -F key=exec
# File access with permission denied
-a always,exit -F arch=b64 -S open,openat,openat2 -F exit=-EACCES -F key=access
-a always,exit -F arch=b64 -S open,openat,openat2 -F exit=-EPERM -F key=access

# File Deletions and Renames
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -F key=delete

# Privilege Escalation
-w /usr/bin/sudo -p x -k priv_esc
-w /bin/su -p x -k priv_esc

# Sensitive File Modifications
-w /etc/passwd -p wa -k identity
-w /etc/group -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# SSH Security
-w /etc/ssh/sshd_config -p wa -k sshd_config_changes
-w /root/.ssh -p wa -k root_ssh_key_changes

# Kernel Module Operations
-a always,exit -F arch=b64 -S init_module,delete_module -F key=modules
-w /sbin/insmod -p x -k modules
-w /sbin/rmmod -p x -k modules
-w /sbin/modprobe -p x -k modules

# Network Configuration
-w /etc/hosts -p wa -k network_modifications
-w /etc/hostname -p wa -k network_modifications
-w /etc/sysctl.conf -p wa -k network_modifications
-w /etc/sysctl.d/ -p wa -k network_modifications

# Network Connection Monitoring
-a always,exit -F arch=b64 -S socket -S connect -F a1!=2 -F key=network_connections

# Make configuration immutable
-e 2
EOF
    
    printf "%b\n" "${GREEN}Audit rules deployed${RC}"
}

enableAuditd() {
    printf "%b\n" "${YELLOW}Enabling auditd service...${RC}"
    
    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would run: systemctl enable --now auditd${RC}"
        return 0
    fi
    
    if systemctl is-active --quiet auditd; then
        printf "%b\n" "${GREEN}auditd is already running${RC}"
        
        # Reload rules if service is already running
        printf "%b\n" "${YELLOW}Reloading audit rules...${RC}"
        "$ESCALATION_TOOL" auditctl -R /etc/audit/rules.d/99-hardening.rules || true
    else
        "$ESCALATION_TOOL" systemctl enable --now auditd
        printf "%b\n" "${GREEN}auditd enabled and started${RC}"
    fi
}

verifyAudit() {
    printf "%b\n" "${YELLOW}Verifying audit configuration...${RC}"
    
    if [ "$DRY_RUN" = "1" ]; then
        printf "%b\n" "${CYAN}[DRY RUN] Would verify audit status${RC}"
        return 0
    fi
    
    if "$ESCALATION_TOOL" systemctl is-active --quiet auditd; then
        RULES_COUNT=$("$ESCALATION_TOOL" auditctl -l 2>/dev/null | grep -c "^-" || echo "0")
        printf "%b\n" "${GREEN}auditd is active with $RULES_COUNT rules loaded${RC}"
    else
        printf "%b\n" "${RED}auditd is not running${RC}"
        return 1
    fi
}

main() {
    printf "%b\n" "${CYAN}Setting up auditd with comprehensive audit rules...${RC}"
    
    installAudit
    deployAuditRules
    enableAuditd
    verifyAudit
    
    printf "%b\n" "${GREEN}auditd setup complete!${RC}"
    printf "%b\n" "${CYAN}View audit events with: sudo ausearch -k <keyword>${RC}"
    printf "%b\n" "${CYAN}Available keywords: exec, access, delete, priv_esc, identity, sudoers, sshd_config_changes, root_ssh_key_changes, modules, network_modifications, network_connections${RC}"
}

main
