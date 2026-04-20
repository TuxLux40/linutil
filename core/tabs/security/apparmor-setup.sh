#!/bin/sh -e

. ../common-script.sh

# -----------------------------------------------------------------------------
# AppArmor setup with bootloader autodetection.
#
# Adds "apparmor" to the kernel lsm= list (the modern approach supported since
# kernel 5.1). Also keeps legacy "apparmor=1 security=apparmor" for very old
# kernels or userspace that parses those.
#
# Supported bootloaders: Limine, systemd-boot, GRUB, rEFInd.
# -----------------------------------------------------------------------------

# --- Kernel cmdline tokens ----------------------------------------------------

LSM_DEFAULT_ORDER="landlock,lockdown,yama,integrity,apparmor,bpf"

# --- State for cleanup --------------------------------------------------------

BOOTLOADER=""
BACKUP_FILE=""
TARGET_CONFIG=""
BOOTLOADER_UPDATED=false

cleanup() {
    if [ "$BOOTLOADER_UPDATED" = "false" ] && [ -n "$BACKUP_FILE" ] && [ -f "$BACKUP_FILE" ] && [ -n "$TARGET_CONFIG" ]; then
        printf "%b\n" "${YELLOW}Unexpected exit — restoring ${TARGET_CONFIG} from backup...${RC}"
        cp "$BACKUP_FILE" "$TARGET_CONFIG" && printf "%b\n" "${GREEN}✓ Backup restored${RC}"
    fi
}
trap cleanup EXIT

# --- Pre-flight checks --------------------------------------------------------

if [ "$(id -u)" -ne 0 ]; then
    printf "%b\n" "${RED}Error: This script must be run as root (use sudo).${RC}"
    exit 1
fi

checkEscalationTool
checkPackageManager 'nala apt-get dnf pacman zypper apk xbps-install eopkg'

# --- Detect bootloader --------------------------------------------------------

detect_bootloader() {
    # Preference order: what's actually running > what config files exist.
    if command -v bootctl > /dev/null 2>&1; then
        CURRENT=$(bootctl status 2>/dev/null | awk '/Current Boot Loader/{getline; print}' | awk -F: '{print $2}' | tr -d ' ')
        case "$CURRENT" in
            *Limine*)      BOOTLOADER="limine";      return ;;
            *systemd-boot*) BOOTLOADER="systemd-boot"; return ;;
            *GRUB*|*grub*)  BOOTLOADER="grub";         return ;;
            *rEFInd*|*refind*) BOOTLOADER="refind";    return ;;
        esac
    fi

    # Fallback: config file presence
    if [ -f /etc/default/limine ] || command -v limine-update > /dev/null 2>&1; then
        BOOTLOADER="limine"; return
    fi
    if [ -d /boot/loader/entries ] || [ -f /etc/kernel/cmdline ]; then
        BOOTLOADER="systemd-boot"; return
    fi
    if [ -f /etc/default/grub ]; then
        BOOTLOADER="grub"; return
    fi
    if [ -f /boot/refind_linux.conf ] || [ -f /boot/EFI/refind/refind.conf ]; then
        BOOTLOADER="refind"; return
    fi

    BOOTLOADER="unknown"
}

# --- Install apparmor package if missing --------------------------------------

ensure_apparmor_installed() {
    if command -v apparmor_parser > /dev/null 2>&1; then
        return 0
    fi
    printf "%b\n" "${YELLOW}AppArmor not installed. Installing...${RC}"
    case "$PACKAGER" in
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm apparmor
            ;;
        apt|apt-get)
            "$ESCALATION_TOOL" "$PACKAGER" install -y apparmor apparmor-utils
            ;;
        dnf|yum)
            "$ESCALATION_TOOL" "$PACKAGER" install -y apparmor-parser apparmor-utils
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" install -y apparmor-parser apparmor-utils
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy apparmor
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER. Install 'apparmor' manually.${RC}"
            exit 1
            ;;
    esac
}

# --- Check kernel has AppArmor compiled in ------------------------------------

check_kernel_support() {
    CONFIG=""
    if [ -r "/boot/config-$(uname -r)" ]; then
        CONFIG="/boot/config-$(uname -r)"
    elif [ -r "/proc/config.gz" ]; then
        CONFIG="/proc/config.gz"
    fi
    if [ -z "$CONFIG" ]; then
        printf "%b\n" "${YELLOW}Cannot verify kernel AppArmor support (no config found). Continuing.${RC}"
        return
    fi
    CAT="cat"
    [ "$CONFIG" = "/proc/config.gz" ] && CAT="zcat"
    if ! $CAT "$CONFIG" | grep -q '^CONFIG_SECURITY_APPARMOR=y'; then
        printf "%b\n" "${RED}Kernel lacks CONFIG_SECURITY_APPARMOR=y. Install an apparmor-capable kernel first.${RC}"
        exit 1
    fi
}

# --- Merge apparmor into an lsm= value or append lsm= when absent -------------

merge_lsm_in_cmdline() {
    # Takes a cmdline string on stdin, prints modified cmdline on stdout.
    awk -v order="$LSM_DEFAULT_ORDER" '
    {
        out = ""
        have_lsm = 0
        n = split($0, toks, /[[:space:]]+/)
        for (i = 1; i <= n; i++) {
            t = toks[i]
            if (t == "") continue
            if (t ~ /^lsm=/) {
                have_lsm = 1
                val = substr(t, 5)
                if (val !~ /(^|,)apparmor(,|$)/) {
                    val = val ",apparmor"
                }
                t = "lsm=" val
            }
            out = (out == "" ? t : out " " t)
        }
        if (!have_lsm) {
            out = (out == "" ? "lsm=" order : out " lsm=" order)
        }
        print out
    }'
}

has_apparmor_token() {
    # stdin: cmdline. Returns 0 if apparmor already in lsm= list.
    awk '
    {
        for (i = 1; i <= NF; i++) {
            if ($i ~ /^lsm=/) {
                val = substr($i, 5)
                if (val ~ /(^|,)apparmor(,|$)/) exit 0
            }
        }
        exit 1
    }'
}

# --- Limine handling ----------------------------------------------------------

setup_limine() {
    TARGET_CONFIG="/etc/default/limine"
    if [ ! -f "$TARGET_CONFIG" ]; then
        printf "%b\n" "${RED}Error: $TARGET_CONFIG not found.${RC}"
        exit 1
    fi

    if grep -q 'lsm=[^"]*apparmor' "$TARGET_CONFIG"; then
        printf "%b\n" "${GREEN}✓ Limine already has apparmor in lsm=. Skipping cmdline edit.${RC}"
    else
        BACKUP_FILE="${TARGET_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        printf "%b\n" "${YELLOW}Backup: ${BACKUP_FILE}${RC}"
        cp "$TARGET_CONFIG" "$BACKUP_FILE"

        # Try to merge into existing KERNEL_CMDLINE[default] line that contains lsm=.
        # Otherwise append a new drop-in line.
        if grep -qE '^KERNEL_CMDLINE\[default\].*lsm=' "$TARGET_CONFIG"; then
            # Merge apparmor into existing lsm= value on the matching line.
            # Use python/awk to rewrite just that line for correctness.
            awk '
            /^KERNEL_CMDLINE\[default\].*lsm=/ && !done {
                if (match($0, /lsm=[^ "'"'"']+/)) {
                    tok = substr($0, RSTART, RLENGTH)
                    val = substr(tok, 5)
                    if (val !~ /(^|,)apparmor(,|$)/) {
                        newtok = "lsm=" val ",apparmor"
                        $0 = substr($0, 1, RSTART - 1) newtok substr($0, RSTART + RLENGTH)
                    }
                    done = 1
                }
            }
            { print }
            ' "$BACKUP_FILE" > "$TARGET_CONFIG"
        else
            printf '\n# Added by linutil apparmor-setup\nKERNEL_CMDLINE[default]+="lsm=%s"\n' "$LSM_DEFAULT_ORDER" >> "$TARGET_CONFIG"
        fi

        printf "%b\n" "${GREEN}✓ Limine config updated.${RC}"
    fi

    printf "%b\n" "${YELLOW}Running limine-update...${RC}"
    if ! command -v limine-update > /dev/null 2>&1; then
        printf "%b\n" "${RED}limine-update not found. Install 'limine' package.${RC}"
        exit 1
    fi
    limine-update
    BOOTLOADER_UPDATED=true
}

# --- systemd-boot handling ----------------------------------------------------

setup_systemd_boot() {
    # Strategy:
    # 1. If /etc/kernel/cmdline exists, that's the canonical source. Edit it.
    #    Regenerate entries via kernel-install or mkinitcpio (distro-specific).
    # 2. Otherwise edit each entry's "options" line in /boot/loader/entries/.
    #    Skip snapshot/rollback entries (they often have their own cmdline).
    if [ -f /etc/kernel/cmdline ]; then
        TARGET_CONFIG="/etc/kernel/cmdline"
        BACKUP_FILE="${TARGET_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$TARGET_CONFIG" "$BACKUP_FILE"

        CURRENT=$(tr -d '\n' < "$TARGET_CONFIG")
        if printf '%s\n' "$CURRENT" | has_apparmor_token; then
            printf "%b\n" "${GREEN}✓ /etc/kernel/cmdline already has apparmor in lsm=. Skipping.${RC}"
        else
            NEW=$(printf '%s\n' "$CURRENT" | merge_lsm_in_cmdline)
            printf '%s\n' "$NEW" > "$TARGET_CONFIG"
            printf "%b\n" "${GREEN}✓ /etc/kernel/cmdline updated.${RC}"
        fi

        # Regenerate initramfs/UKI/entries however the distro does it.
        if command -v reinstall-kernels > /dev/null 2>&1; then
            reinstall-kernels
        elif command -v kernel-install > /dev/null 2>&1; then
            find /lib/modules -maxdepth 1 -mindepth 1 -type d 2>/dev/null | while IFS= read -r k; do
                ver=$(basename "$k")
                [ -f "$k/vmlinuz" ] && kernel-install add "$ver" "$k/vmlinuz" || true
            done
        elif command -v mkinitcpio > /dev/null 2>&1; then
            mkinitcpio -P
        fi
        BOOTLOADER_UPDATED=true
        return
    fi

    if [ -d /boot/loader/entries ]; then
        TARGET_CONFIG="/boot/loader/entries"
        TIMESTAMP=$(date +%Y%m%d_%H%M%S)
        BACKUP_FILE="${TARGET_CONFIG}.backup.${TIMESTAMP}.tar"
        tar -cf "$BACKUP_FILE" -C /boot/loader entries
        printf "%b\n" "${YELLOW}Backup: ${BACKUP_FILE}${RC}"

        CHANGED=0
        for entry in /boot/loader/entries/*.conf; do
            [ -f "$entry" ] || continue
            # Skip snapshot/rollback entries if identifiable.
            case "$(basename "$entry")" in
                *snapshot*|*rollback*) continue ;;
            esac
            OPTS=$(awk '/^options /{sub(/^options[[:space:]]+/,""); print; exit}' "$entry")
            [ -z "$OPTS" ] && continue
            if printf '%s\n' "$OPTS" | has_apparmor_token; then
                continue
            fi
            NEW=$(printf '%s\n' "$OPTS" | merge_lsm_in_cmdline)
            # Replace options line atomically.
            TMP=$(mktemp)
            awk -v new="$NEW" '
                /^options / { print "options " new; next }
                { print }
            ' "$entry" > "$TMP"
            mv "$TMP" "$entry"
            CHANGED=$((CHANGED + 1))
        done
        printf "%b\n" "${GREEN}✓ systemd-boot: updated $CHANGED entries.${RC}"
        command -v bootctl > /dev/null 2>&1 && bootctl update 2>/dev/null || true
        BOOTLOADER_UPDATED=true
        return
    fi

    printf "%b\n" "${RED}systemd-boot detected but no config source found.${RC}"
    exit 1
}

# --- GRUB handling ------------------------------------------------------------

setup_grub() {
    TARGET_CONFIG="/etc/default/grub"
    if [ ! -f "$TARGET_CONFIG" ]; then
        printf "%b\n" "${RED}Error: $TARGET_CONFIG not found.${RC}"
        exit 1
    fi
    if ! grep -q '^GRUB_CMDLINE_LINUX_DEFAULT=' "$TARGET_CONFIG"; then
        printf "%b\n" "${RED}GRUB_CMDLINE_LINUX_DEFAULT not found.${RC}"
        exit 1
    fi

    CURRENT=$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "$TARGET_CONFIG" | head -n 1 | cut -d'"' -f2)
    if printf '%s\n' "$CURRENT" | has_apparmor_token; then
        printf "%b\n" "${GREEN}✓ GRUB cmdline already has apparmor in lsm=. Skipping cmdline edit.${RC}"
    else
        BACKUP_FILE="${TARGET_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
        cp "$TARGET_CONFIG" "$BACKUP_FILE"
        printf "%b\n" "${YELLOW}Backup: ${BACKUP_FILE}${RC}"

        NEW=$(printf '%s\n' "$CURRENT" | merge_lsm_in_cmdline | sed 's/^[[:space:]]*//')
        printf "%b\n" "${YELLOW}Old cmdline: ${RC}%s\n" "$CURRENT"
        printf "%b\n" "${YELLOW}New cmdline: ${RC}%s\n" "$NEW"

        # Use awk to replace the line; avoids sed quoting headaches.
        TMP=$(mktemp)
        awk -v new="$NEW" '
            /^GRUB_CMDLINE_LINUX_DEFAULT=/ && !done { print "GRUB_CMDLINE_LINUX_DEFAULT=\"" new "\""; done=1; next }
            { print }
        ' "$TARGET_CONFIG" > "$TMP"
        mv "$TMP" "$TARGET_CONFIG"
    fi

    GRUB_CFG=""
    for path in /boot/grub/grub.cfg /boot/grub2/grub.cfg; do
        [ -f "$path" ] && { GRUB_CFG="$path"; break; }
    done

    printf "%b\n" "${YELLOW}Regenerating GRUB config...${RC}"
    if command -v update-grub > /dev/null 2>&1; then
        update-grub
    elif command -v grub-mkconfig > /dev/null 2>&1 && [ -n "$GRUB_CFG" ]; then
        grub-mkconfig -o "$GRUB_CFG"
    elif command -v grub2-mkconfig > /dev/null 2>&1 && [ -n "$GRUB_CFG" ]; then
        grub2-mkconfig -o "$GRUB_CFG"
    else
        printf "%b\n" "${RED}No GRUB regen command found. Run grub-mkconfig manually.${RC}"
        exit 1
    fi
    BOOTLOADER_UPDATED=true
}

# --- rEFInd handling ----------------------------------------------------------

setup_refind() {
    # rEFInd reads cmdline from multiple places depending on setup:
    # 1. /boot/refind_linux.conf (when using manual-boot-stanzas with kernel autodetect)
    # 2. /boot/EFI/refind/refind.conf (via 'options' in manual 'menuentry' blocks)
    # Prefer refind_linux.conf since it's the common userspace-managed file.
    if [ -f /boot/refind_linux.conf ]; then
        TARGET_CONFIG="/boot/refind_linux.conf"
    elif [ -f /boot/EFI/refind/refind.conf ]; then
        TARGET_CONFIG="/boot/EFI/refind/refind.conf"
    else
        printf "%b\n" "${RED}No rEFInd config found at /boot/refind_linux.conf or /boot/EFI/refind/refind.conf.${RC}"
        exit 1
    fi

    BACKUP_FILE="${TARGET_CONFIG}.backup.$(date +%Y%m%d_%H%M%S)"
    cp "$TARGET_CONFIG" "$BACKUP_FILE"
    printf "%b\n" "${YELLOW}Backup: ${BACKUP_FILE}${RC}"

    if grep -q 'lsm=[^"]*apparmor' "$TARGET_CONFIG"; then
        printf "%b\n" "${GREEN}✓ rEFInd config already has apparmor in lsm=.${RC}"
    else
        # Append lsm= at end of each quoted cmdline string on a "Boot with" line (refind_linux.conf)
        # or each "options" line (refind.conf). Keep it simple: append to any double-quoted string on lines we care about.
        TMP=$(mktemp)
        awk -v order="$LSM_DEFAULT_ORDER" '
        function merge_q(line) {
            # Find first "..." and append lsm=<order>,apparmor or add apparmor to existing lsm=
            if (match(line, /"[^"]*"/)) {
                inside = substr(line, RSTART + 1, RLENGTH - 2)
                if (inside ~ /lsm=[^ ]*/) {
                    if (inside !~ /lsm=[^ ]*apparmor/) {
                        sub(/lsm=[^ ]*/, "&,apparmor", inside)
                    }
                } else {
                    inside = inside " lsm=" order
                }
                return substr(line, 1, RSTART - 1) "\"" inside "\"" substr(line, RSTART + RLENGTH)
            }
            return line
        }
        /^"[^"]*"[[:space:]]+"/ || /^[[:space:]]*options[[:space:]]+/ {
            print merge_q($0); next
        }
        { print }
        ' "$TARGET_CONFIG" > "$TMP"
        mv "$TMP" "$TARGET_CONFIG"
        printf "%b\n" "${GREEN}✓ rEFInd config updated.${RC}"
    fi
    # rEFInd reads config at boot directly; nothing to regenerate.
    BOOTLOADER_UPDATED=true
}

# --- Main flow ----------------------------------------------------------------

ensure_apparmor_installed
check_kernel_support
detect_bootloader

printf "%b\n" "${CYAN}Detected bootloader: ${BOOTLOADER}${RC}"

printf "%b\n" "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
printf "%b\n" "${RED}  WARNING: MODIFYING BOOTLOADER CONFIG${RC}"
printf "%b\n" "${RED}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RC}"
printf "%b\n" "${YELLOW}This adds apparmor to the kernel lsm= list. If misapplied the system may not boot.${RC}"
printf "%b\n" "${YELLOW}A backup of the edited config will be created. Have recovery media ready.${RC}"
printf "\n"
printf "%b" "Type 'I UNDERSTAND THE RISKS' to continue: "
read -r confirmation
if [ "$confirmation" != "I UNDERSTAND THE RISKS" ]; then
    printf "%b\n" "${RED}Aborted.${RC}"
    exit 1
fi

case "$BOOTLOADER" in
    limine)       setup_limine ;;
    systemd-boot) setup_systemd_boot ;;
    grub)         setup_grub ;;
    refind)       setup_refind ;;
    *)
        printf "%b\n" "${RED}Unsupported or unknown bootloader. Edit the kernel cmdline manually:${RC}"
        printf "%b\n" "  Add: lsm=${LSM_DEFAULT_ORDER}"
        exit 1
        ;;
esac

# --- Install extended profile set --------------------------------------------
#
# Base apparmor pkg on most distros ships only a small profile set. Extended
# profile packages cover desktop apps (browsers, chat, editors, etc).
# All installed in complain mode by default — log-only, no breakage.

install_extended_profiles() {
    case "$PACKAGER" in
        pacman)
            # apparmor.d-git: roddhjav/apparmor.d, ~2000 profiles.
            # Available in chaotic-aur, cachyos repos, and AUR.
            if pacman -Qi apparmor.d-git > /dev/null 2>&1 || pacman -Qi apparmor.d > /dev/null 2>&1; then
                printf "%b\n" "${GREEN}✓ Extended profiles already installed.${RC}"
                return
            fi
            if pacman -Si apparmor.d-git > /dev/null 2>&1; then
                printf "%b\n" "${YELLOW}Installing apparmor.d-git from configured repos...${RC}"
                pacman -S --needed --noconfirm apparmor.d-git
            elif pacman -Si apparmor.d > /dev/null 2>&1; then
                printf "%b\n" "${YELLOW}Installing apparmor.d from configured repos...${RC}"
                pacman -S --needed --noconfirm apparmor.d
            else
                checkAURHelper
                printf "%b\n" "${YELLOW}Installing apparmor.d-git from AUR via ${AUR_HELPER}...${RC}"
                # AUR helpers refuse to run as root; re-exec as invoking user if possible.
                if [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ]; then
                    su - "$SUDO_USER" -c "$AUR_HELPER -S --noconfirm apparmor.d-git"
                else
                    printf "%b\n" "${RED}Cannot install AUR package as root without SUDO_USER. Run '${AUR_HELPER} -S apparmor.d-git' as your user.${RC}"
                fi
            fi
            # apparmor.d requires cache-loc configured for early policy.
            if [ -f /etc/apparmor/parser.conf ] && ! grep -q '^cache-loc' /etc/apparmor/parser.conf; then
                printf "%b\n" "${YELLOW}Configuring apparmor parser cache-loc for early policy...${RC}"
                mkdir -p /etc/apparmor/earlypolicy/
                printf '\n# Added by linutil apparmor-setup\ncache-loc /etc/apparmor/earlypolicy/\nwrite-cache\n' >> /etc/apparmor/parser.conf
            fi
            ;;
        apt|apt-get)
            printf "%b\n" "${YELLOW}Installing apparmor-profiles and apparmor-profiles-extra...${RC}"
            "$PACKAGER" install -y apparmor-profiles apparmor-profiles-extra || true
            ;;
        dnf|yum)
            # Fedora's apparmor-parser pkg already includes a reasonable profile set.
            printf "%b\n" "${CYAN}Fedora: extended profiles bundled with base apparmor pkg.${RC}"
            ;;
        zypper)
            # openSUSE ships profiles in apparmor-profiles.
            printf "%b\n" "${YELLOW}Installing apparmor-profiles...${RC}"
            "$PACKAGER" install -y apparmor-profiles || true
            ;;
        *)
            printf "%b\n" "${YELLOW}No extended profile set known for $PACKAGER. Skipping.${RC}"
            ;;
    esac
}

printf "%b\n" "${YELLOW}Installing extended AppArmor profile set...${RC}"
install_extended_profiles

# --- Install AppAnvil GUI from fork ------------------------------------------
#
# AppAnvil is a GTK frontend for managing apparmor profiles. Upstream's CMake
# installs aa-caller into sbin/ which conflicts on merged-usr distros (Arch,
# Fedora). The fork at github.com/TuxLux40/AppAnvil fixes this — build from
# source there.

APPANVIL_FORK_URL="https://github.com/TuxLux40/AppAnvil.git"
APPANVIL_FORK_REF="main"

install_appanvil_build_deps() {
    case "$PACKAGER" in
        pacman)
            "$PACKAGER" -S --needed --noconfirm \
                cmake base-devel git pkgconf \
                gtkmm3 jsoncpp apparmor
            ;;
        apt|apt-get)
            "$PACKAGER" install -y \
                cmake git pkg-config g++ bison flex \
                libgtkmm-3.0-dev libjsoncpp-dev libapparmor-dev apparmor-utils
            ;;
        dnf|yum)
            "$PACKAGER" install -y \
                cmake git gcc-c++ bison flex pkgconf-pkg-config \
                gtkmm30-devel jsoncpp-devel libapparmor-devel
            ;;
        zypper)
            "$PACKAGER" install -y \
                cmake git gcc-c++ bison flex pkg-config \
                gtkmm3-devel jsoncpp-devel libapparmor-devel
            ;;
        *)
            printf "%b\n" "${YELLOW}No build deps mapping for $PACKAGER. Install cmake + gtkmm3 + jsoncpp + libapparmor dev pkgs manually.${RC}"
            return 1
            ;;
    esac
}

install_appanvil() {
    if command -v appanvil > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ AppAnvil already installed.${RC}"
        return 0
    fi
    printf "%b\n" "${YELLOW}Building AppAnvil from ${APPANVIL_FORK_URL} (${APPANVIL_FORK_REF})...${RC}"

    install_appanvil_build_deps || { printf "%b\n" "${RED}AppAnvil build deps failed. Skipping.${RC}"; return 1; }

    # Build as invoking user, install as root.
    BUILD_USER="${SUDO_USER:-$(logname 2>/dev/null || echo root)}"
    BUILD_DIR=$(mktemp -d -t appanvil.XXXXXX)
    chown "$BUILD_USER:$BUILD_USER" "$BUILD_DIR"

    # shellcheck disable=SC2016
    su - "$BUILD_USER" -c '
        set -e
        cd "'"$BUILD_DIR"'"
        git clone --depth 1 --branch "'"$APPANVIL_FORK_REF"'" "'"$APPANVIL_FORK_URL"'" AppAnvil
        cd AppAnvil
        git submodule update --init --recursive
        cmake -DCMAKE_BUILD_TYPE=Release -DCMAKE_INSTALL_PREFIX=/usr .
        make -j"$(nproc)"
    ' || { printf "%b\n" "${RED}AppAnvil build failed.${RC}"; rm -rf "$BUILD_DIR"; return 1; }

    ( cd "$BUILD_DIR/AppAnvil" && make install )
    rm -rf "$BUILD_DIR"

    if command -v appanvil > /dev/null 2>&1; then
        printf "%b\n" "${GREEN}✓ AppAnvil installed to $(command -v appanvil).${RC}"
    else
        printf "%b\n" "${RED}AppAnvil install completed but binary not found on PATH.${RC}"
        return 1
    fi
}

install_appanvil || true

# --- Enable service -----------------------------------------------------------

if command -v systemctl > /dev/null 2>&1; then
    if ! systemctl is-enabled apparmor.service > /dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Enabling apparmor.service...${RC}"
        systemctl enable apparmor.service
    fi
    # Reload now so new profiles are active without needing reboot (LSM still
    # needs reboot, but profiles can be loaded into the running kernel).
    if systemctl is-active apparmor.service > /dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Reloading apparmor.service to pick up new profiles...${RC}"
        systemctl reload apparmor.service 2>/dev/null || systemctl restart apparmor.service || true
    fi
fi

# --- Summary ------------------------------------------------------------------

printf "\n"
printf "%b\n" "${GREEN}✓ AppArmor boot setup complete (${BOOTLOADER}).${RC}"
printf "%b\n" "${YELLOW}Backup: ${BACKUP_FILE:-none}${RC}"
printf "\n"
printf "%b\n" "${YELLOW}Reboot required. After reboot verify with:${RC}"
printf "  cat /sys/kernel/security/lsm    # should list apparmor\n"
printf "  aa-status                        # lists loaded profiles\n"
printf "\n"
printf "%b\n" "${GREEN}Recovery if boot fails:${RC}"
printf "  - Limine:       pick a 'Snapshot' entry from the menu\n"
printf "  - systemd-boot: press 'e' at entry to edit cmdline; remove lsm= token\n"
printf "  - GRUB:         press 'e' at entry to edit cmdline; remove lsm= token\n"
printf "  - Boot a live USB, mount /, and restore: cp BACKUP <config>\n"
