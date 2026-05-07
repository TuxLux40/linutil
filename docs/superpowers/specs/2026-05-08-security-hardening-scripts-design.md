# Security Hardening Scripts — Design Spec

**Date:** 2026-05-08
**Status:** Approved

## Overview

Seven new scripts for linutil's Security tab. Covers kernel hardening, SSH, auditd, process isolation, PAM policy, USBGuard, and login banners. Portable across distros via `$PACKAGER`. Idempotent — safe to re-run. Smart context detection avoids breaking running services or hardware. Supports `--dry-run` and confirms before breaking changes.

---

## Architecture

### Conventions

- `#!/bin/sh -e` — POSIX sh, no bashisms
- Source `../common-script.sh` for `$ESCALATION_TOOL`, `$PACKAGER`, color vars
- Each script is fully standalone — no inter-script dependencies

### Shared Behaviors

**Dry-run (`--dry-run`):**
- Sets `DRY_RUN=1`
- All file writes replaced with `printf` showing what would be written
- Service restarts print the command, do not execute
- End-of-script summary: list of changes that would be applied

**Confirm (`confirm_change <description>`):**
- Defined at the top of each script that uses it (no shared file — YAGNI)
- Used only before breaking or hard-to-reverse changes
- Prints description of change, prompts `[y/N]`
- Non-interactive environments (no TTY) default to `N`
- No-op in dry-run mode (change is printed, not confirmed)

**Idempotency pattern:**
- Sysctl: compare live value (`sysctl -n <key>`) with target before writing
- Config files: grep for existing setting/value before sed or append
- Services: `systemctl is-active` before enable/restart
- Print `already set — skipping` when no change needed

### Smart Detection Helpers

```sh
service_active()        # systemctl is-active $1 >/dev/null 2>&1
has_bluetooth()         # test -d /sys/class/bluetooth
docker_or_virt()        # command_exists docker || command_exists podman || service_active libvirtd
```

---

## Scripts

### 1. `kernel-hardening.sh`

**Purpose:** Apply kernel sysctl hardening and blacklist uncommon network protocols.

**Sysctl file:** `/etc/sysctl.d/90-hardening.conf`

| Key | Value | Skip condition |
|-----|-------|----------------|
| `net.core.bpf_jit_harden` | 2 | — |
| `fs.protected_fifos` | 2 | — |
| `fs.protected_regular` | 2 | — |
| `fs.suid_dumpable` | 0 | — |
| `net.ipv4.conf.all.log_martians` | 1 | — |
| `net.ipv4.conf.default.log_martians` | 1 | — |
| `net.ipv4.conf.all.send_redirects` | 0 | `docker_or_virt()` returns true |
| `net.ipv4.conf.all.forwarding` | 0 | `docker_or_virt()` returns true OR `service_active tailscaled` |
| `dev.tty.ldisc_autoload` | 0 | `has_bluetooth()` returns true |
| `kernel.unprivileged_bpf_disabled` | 1 | already ≥ 1 |

**Module blacklist:** `/etc/modprobe.d/blacklist-uncommon-net.conf`
```
install dccp /bin/false
install sctp /bin/false
install rds /bin/false
install tipc /bin/false
```
Idempotent: check if entry already present before appending.

**Confirm:** None — all changes reversible.

**Tab entry:**
```toml
[[data]]
name = "Kernel Hardening"
description = "Applies sysctl hardening (BPF, file protection, martian logging, redirect blocking) and blacklists unused network protocols (dccp, sctp, rds, tipc). Smart: skips forwarding/ldisc changes if Docker/libvirt/Bluetooth detected."
script = "kernel-hardening.sh"
task_list = ""
```

---

### 2. `ssh-hardening.sh`

**Purpose:** Harden OpenSSH server configuration.

**Skip entirely:** if `sshd` not installed (`command_exists sshd` false).

**Backup:** `sshd_config.bak.<timestamp>` before any changes.

**Settings applied** (grep before each; skip if already set to target):

| Option | Target |
|--------|--------|
| `AllowTcpForwarding` | no |
| `AllowAgentForwarding` | no |
| `ClientAliveCountMax` | 2 |
| `MaxAuthTries` | 3 |
| `MaxSessions` | 2 |
| `LogLevel` | VERBOSE |
| `TCPKeepAlive` | no |
| `PrintLastLog` | yes |

**Confirm:** If current `Port` is 22 AND `tailscaled` is not active — warn before any port change suggestion. Script does not change port automatically; prints recommendation only.

**Post-apply:** `systemctl restart sshd` (skipped in dry-run).

**Tab entry:**
```toml
[[data]]
name = "SSH Hardening"
description = "Hardens sshd_config: disables TCP/agent forwarding, tightens auth limits, enables verbose logging. Backs up config before changes. Skipped if sshd is not installed."
script = "ssh-hardening.sh"
task_list = "SS"
```

---

### 3. `auditd-setup.sh`

**Purpose:** Install auditd and deploy a baseline audit ruleset.

**Install:** `audit` package via `$PACKAGER`. Skip if already installed.

**Rules file:** `/etc/audit/rules.d/99-hardening.rules`

```
# Delete operations
-a always,exit -F arch=b64 -S unlink -S unlinkat -S rename -S renameat -k delete

# Privilege escalation
-w /usr/bin/sudo -p x -k priv_esc
-w /bin/su -p x -k priv_esc

# Sensitive file modifications
-w /etc/passwd -p wa -k identity
-w /etc/shadow -p wa -k identity
-w /etc/sudoers -p wa -k sudoers
-w /etc/sudoers.d/ -p wa -k sudoers

# Kernel module operations
-a always,exit -F arch=b64 -S init_module -S delete_module -k modules

# Failed login attempts
-a always,exit -F arch=b64 -S open -F exit=-EACCES -k access
-a always,exit -F arch=b64 -S open -F exit=-EPERM -k access
```

Idempotent: skip if rules file exists and content matches (md5/sha check or grep key rules).

**Enable:** `systemctl enable --now auditd`.

**Confirm:** None — additive only.

**Tab entry:**
```toml
[[data]]
name = "Auditd Setup"
description = "Installs auditd and deploys baseline audit rules: file deletions, privilege escalation, sensitive file changes (passwd/shadow/sudoers), kernel module operations, and failed access attempts."
script = "auditd-setup.sh"
task_list = "I SS"
```

---

### 4. `proc-hardening.sh`

**Purpose:** Prevent core dumps from sensitive processes and hide other users' processes in /proc.

**Core dump hardening:**
- Append `* hard core 0` and `* soft core 0` to `/etc/security/limits.conf` if not present
- Write `/etc/systemd/coredump.conf.d/hardening.conf`:
  ```ini
  [Coredump]
  Storage=none
  ProcessSizeMax=0
  ```

**hidepid:**
- Create `proc` group if absent
- Add current user (`$SUDO_USER` or `$USER`) to `proc` group
- Write `/etc/systemd/system/proc.mount.d/hardening.conf`:
  ```ini
  [Mount]
  Options=nosuid,nodev,noexec,relatime,hidepid=2,gid=proc
  ```
- Reload systemd, remount /proc

**Confirm:** hidepid — message: "hidepid=2 hides other users' processes. Some system monitoring tools may fail unless added to the 'proc' group. Current user will be added automatically."

**Tab entry:**
```toml
[[data]]
name = "Process Hardening"
description = "Disables core dumps for setuid processes and enables hidepid=2 on /proc to hide other users' processes. Adds current user to the 'proc' group automatically."
script = "proc-hardening.sh"
task_list = ""
```

---

### 5. `pam-hardening.sh`

**Purpose:** Enforce password policy via login.defs and pam_pwquality.

**login.defs changes** (sed in-place, only if current value differs):

| Key | Value |
|-----|-------|
| `UMASK` | 027 |
| `PASS_MAX_DAYS` | 365 |
| `PASS_MIN_DAYS` | 1 |
| `ENCRYPT_METHOD` | YESCRYPT (fallback SHA512 if yescrypt not supported) |

**pwquality:**
- Install `libpwquality` (pacman) / `libpam-pwquality` (apt) / `libpwquality` (dnf)
- Write `/etc/security/pwquality.conf`:
  ```
  minlen = 12
  dcredit = -1
  ucredit = -1
  lcredit = -1
  ocredit = -1
  ```
- Idempotent: skip if file exists with matching values

**Confirm:** password aging — "PASS_MAX_DAYS/PASS_MIN_DAYS apply to new passwords only. Existing accounts are unaffected until next password change."

**Tab entry:**
```toml
[[data]]
name = "PAM Hardening"
description = "Sets password policy: 12-char minimum, complexity requirements via pam_pwquality, 365-day max age, stricter umask (027). Uses yescrypt hashing if available."
script = "pam-hardening.sh"
task_list = "I"
```

---

### 6. `usbguard-setup.sh`

**Purpose:** Install USBGuard and generate an allowlist from currently connected devices.

**Install:** `usbguard` via `$PACKAGER`. Skip if already installed and service active with policy.

**Policy generation:**
```sh
usbguard generate-policy > /etc/usbguard/rules.conf
```
Run before enabling service so currently connected keyboard/mouse are allowed.

**Enable:** `systemctl enable --now usbguard`.

**Confirm:** Always — message: "USBGuard will block USB devices not currently connected. Ensure your keyboard and mouse are plugged in NOW. New devices will be blocked until manually authorized with 'usbguard allow-device'."

**Tab entry:**
```toml
[[data]]
name = "USBGuard Setup"
description = "Installs USBGuard and generates an allowlist from currently-connected USB devices. New USB devices will be blocked until explicitly authorized."
script = "usbguard-setup.sh"
task_list = "I SS"
```

---

### 7. `login-banner.sh`

**Purpose:** Write a legal warning banner to /etc/issue and /etc/issue.net.

**Banner content:**
```
*******************************************************************************
NOTICE: This system is for authorized use only. Unauthorized access or use
is prohibited and may result in disciplinary action and/or civil and criminal
penalties. All activity on this system may be monitored and recorded.
*******************************************************************************
```

**Idempotency:** Skip if `/etc/issue` already contains more than the distro default (check line count > 3 or presence of "NOTICE"/"authorized").

**SSH integration:** If sshd installed, set `Banner /etc/issue.net` in `sshd_config` and restart sshd.

**Confirm:** None.

**Tab entry:**
```toml
[[data]]
name = "Login Banner"
description = "Writes a legal warning banner to /etc/issue and /etc/issue.net. If sshd is installed, configures it to display the banner at login."
script = "login-banner.sh"
task_list = ""
```

---

## tab_data.toml additions

Add after existing entries:

```toml
[[data]]
name = "Kernel Hardening"
description = "Applies sysctl hardening (BPF, file protection, martian logging, redirect blocking) and blacklists unused network protocols (dccp, sctp, rds, tipc). Smart: skips forwarding/ldisc changes if Docker/libvirt/Bluetooth detected."
script = "kernel-hardening.sh"
task_list = ""

[[data]]
name = "SSH Hardening"
description = "Hardens sshd_config: disables TCP/agent forwarding, tightens auth limits, enables verbose logging. Backs up config before changes. Skipped if sshd is not installed."
script = "ssh-hardening.sh"
task_list = "SS"

[[data]]
name = "Auditd Setup"
description = "Installs auditd and deploys baseline audit rules: file deletions, privilege escalation, sensitive file changes (passwd/shadow/sudoers), kernel module operations, and failed access attempts."
script = "auditd-setup.sh"
task_list = "I SS"

[[data]]
name = "Process Hardening"
description = "Disables core dumps for setuid processes and enables hidepid=2 on /proc to hide other users' processes. Adds current user to the 'proc' group automatically."
script = "proc-hardening.sh"
task_list = ""

[[data]]
name = "PAM Hardening"
description = "Sets password policy: 12-char minimum, complexity requirements via pam_pwquality, 365-day max age, stricter umask (027). Uses yescrypt hashing if available."
script = "pam-hardening.sh"
task_list = "I"

[[data]]
name = "USBGuard Setup"
description = "Installs USBGuard and generates an allowlist from currently-connected USB devices. New USB devices will be blocked until explicitly authorized."
script = "usbguard-setup.sh"
task_list = "I SS"

[[data]]
name = "Login Banner"
description = "Writes a legal warning banner to /etc/issue and /etc/issue.net. If sshd is installed, configures it to display the banner at login."
script = "login-banner.sh"
task_list = ""
```

---

## Out of Scope

- AIDE (separate script, already tracked)
- Lynis (separate script, already tracked)
- AppArmor, ClamAV, UFW, FirewallD, YubiKey PAM (existing)
- Compiler access restriction (too disruptive for dev systems without opt-in)
- `/var` separate partition (requires repartitioning)
- Fail2ban (overlaps with UFW/FirewallD rate limiting; separate concern)
