#!/bin/sh
# Install Entware on Synology NAS
# Source: https://github-wiki-see.page/m/entware/entware/wiki/Install-on-Synology-NAS

ENTWARE_ROOT="/volume1/@Entware"
ENTWARE_OPT="${ENTWARE_ROOT}/opt"
ENTWARE_FORCE_REMOVE_OPT="${ENTWARE_FORCE_REMOVE_OPT:-0}"
ENTWARE_BACKUP_OPT="${ENTWARE_BACKUP_OPT:-0}"

print_info() {
	printf "%b\n" "$1"
}

require_root() {
	if [ "$(id -u)" != "0" ]; then
		print_info "This script must be run as root."
		exit 1
	fi
}

detect_arch() {
	case "$(uname -m)" in
		aarch64|arm64)
			ENTWARE_ARCH="aarch64-k3.10"
			;;
		armv5*|armv5te*|armv5tel)
			ENTWARE_ARCH="armv5sf-k3.2"
			;;
		armv7*|armv7l)
			ENTWARE_ARCH="armv7sf-k3.2"
			;;
		x86_64|amd64)
			ENTWARE_ARCH="x64-k3.2"
			;;
		*)
			print_info "Unsupported architecture: $(uname -m)."
			print_info "Check the Entware Synology guide for supported builds."
			exit 1
			;;
	esac

	ENTWARE_URL="https://bin.entware.net/${ENTWARE_ARCH}/installer/generic.sh"
}

ensure_opt_mount() {
	print_info "Creating ${ENTWARE_OPT}..."
	mkdir -p "${ENTWARE_OPT}"

	if mount | grep -q " on /opt "; then
		if mount | grep -q "${ENTWARE_OPT}"; then
			print_info "/opt is already bound to ${ENTWARE_OPT}."
			return 0
		fi

		print_info "Detected an existing mount on /opt that is not Entware."
		print_info "Unmount /opt manually and re-run this script."
		exit 1
	fi

	if [ -L /opt ]; then
		if [ "$(readlink /opt)" = "${ENTWARE_OPT}" ]; then
			print_info "/opt already points to ${ENTWARE_OPT}."
			return 0
		fi
		print_info "/opt is a symlink to a different target. Aborting."
		exit 1
	fi

	if [ -e /opt ] && [ ! -d /opt ]; then
		print_info "/opt exists but is not a directory. Aborting."
		exit 1
	fi

	if [ -d /opt ] && [ "$(ls -A /opt 2>/dev/null)" ]; then
		if [ "${ENTWARE_BACKUP_OPT}" = "1" ]; then
			backup_path="/opt.backup-$(date +%Y%m%d%H%M%S)"
			print_info "Backing up /opt contents to ${backup_path}..."
			mv /opt "${backup_path}"
			mkdir -p /opt
			print_info "Backup complete."
			return 0
		fi

		if [ "${ENTWARE_FORCE_REMOVE_OPT}" != "1" ]; then
			print_info "/opt is not empty. Set ENTWARE_BACKUP_OPT=1 to move it aside or ENTWARE_FORCE_REMOVE_OPT=1 to remove it."
			exit 1
		fi
		print_info "Removing existing /opt contents..."
		rm -rf /opt
	fi

	print_info "Creating /opt and binding ${ENTWARE_OPT} -> /opt..."
	mkdir -p /opt
	mount -o bind "${ENTWARE_OPT}" /opt
}

run_installer() {
	print_info "Downloading and running Entware installer for ${ENTWARE_ARCH}..."

	if command -v wget >/dev/null 2>&1; then
		wget -O - "${ENTWARE_URL}" | /bin/sh
		return 0
	fi

	if command -v curl >/dev/null 2>&1; then
		curl -fsSL "${ENTWARE_URL}" | /bin/sh
		return 0
	fi

	print_info "Neither wget nor curl found. Install one of them and retry."
	exit 1
}

ensure_profile() {
	if grep -qF "/opt/etc/profile" /etc/profile; then
		print_info "Entware profile already present in /etc/profile."
		return 0
	fi

	print_info "Adding Entware profile hook to /etc/profile..."
	cat >> /etc/profile <<"EOF"

# Load Entware Profile
[ -r "/opt/etc/profile" ] && . /opt/etc/profile
EOF
}

start_entware() {
	if [ -x /opt/etc/init.d/rc.unslung ]; then
		print_info "Starting Entware services..."
		/opt/etc/init.d/rc.unslung start
	fi

	if [ -x /opt/bin/opkg ]; then
		print_info "Updating Entware package list..."
		/opt/bin/opkg update
	fi
}

print_autostart_instructions() {
	cat <<'EOF'

Autostart task (DSM GUI)
1) DSM > Control Panel > Task Scheduler
2) Create > Triggered Task > User-defined script
3) General
   - Task: Entware
   - User: root
   - Event: Boot-up
4) Task Settings > Run Command:

#!/bin/sh

mkdir -p /opt
mount -o bind "/volume1/@Entware/opt" /opt
/opt/etc/init.d/rc.unslung start

Tips
- Firmware updates can wipe /opt. The bind mount keeps Entware outside rootfs.
- If you want another task to run after Entware, set its Pre-task to the Entware task.
EOF
}

require_root
detect_arch
ensure_opt_mount
run_installer
ensure_profile
start_entware
print_autostart_instructions
