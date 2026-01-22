#!/bin/sh
set -e

# Minimal Tailscale install + setup

# 1) Install Tailscale via official script if missing
if ! command -v tailscale >/dev/null 2>&1; then
	curl -fsSL https://tailscale.com/install.sh | sh
fi

# 2) Enable and start tailscaled
if command -v systemctl >/dev/null 2>&1; then
	sudo systemctl enable --now tailscaled
fi

# 3) Set operator
# Determine desired operator user (prefer the invoking non-root user)
OPERATOR_USER="${SUDO_USER:-}"
if [ -z "$OPERATOR_USER" ]; then
	OPERATOR_USER="$(logname 2>/dev/null || whoami)"
fi
if [ -n "$OPERATOR_USER" ]; then
	sudo tailscale set --operator="$OPERATOR_USER" || true
fi

# 4) Enable OpenSSH (unit name varies by distro; best-effort)
if command -v systemctl >/dev/null 2>&1; then
	sudo systemctl enable --now ssh.service 2>/dev/null || \
	sudo systemctl enable --now sshd.service 2>/dev/null || true
fi

# 5) Enable IP forwarding
if [ -d /etc/sysctl.d ]; then
	sudo tee /etc/sysctl.d/99-tailscale.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
	sudo sysctl -p /etc/sysctl.d/99-tailscale.conf
else
	sudo sysctl -w net.ipv4.ip_forward=1
	sudo sysctl -w net.ipv6.conf.all.forwarding=1
fi

# 6) Bring Tailscale up
# - Non-interactive if TS_AUTHKEY is set
# - Otherwise try interactive (non-fatal if unattended)
HOSTNAME_ARG=""
if [ -n "${TS_HOSTNAME:-}" ]; then
	HOSTNAME_ARG="--hostname=${TS_HOSTNAME}"
else
	# Use short hostname if available to keep MagicDNS names clean
	SHORT_HOST="$(hostname -s 2>/dev/null || hostname)"
	[ -n "$SHORT_HOST" ] && HOSTNAME_ARG="--hostname=${SHORT_HOST}"
fi

# Always accept DNS to enable MagicDNS on this node; reset prefs to avoid stale settings
UP_FLAGS="--ssh --accept-routes --accept-dns=true ${HOSTNAME_ARG} --reset"

if [ -n "${TS_AUTHKEY:-}" ]; then
	sudo tailscale up ${UP_FLAGS} --authkey="$TS_AUTHKEY"
else
	sudo tailscale up ${UP_FLAGS} || true
fi

# 7) Fix resolv.conf to use systemd-resolved stub resolver
# This ensures MagicDNS works correctly. For further information, see: https://tailscale.com/kb/1188/linux-dns
sudo ln -sf /run/systemd/resolve/stub-resolv.conf /etc/resolv.conf
sleep 1
sudo systemctl restart systemd-resolved
sleep 1
sudo systemctl restart NetworkManager
sleep 1
sudo systemctl restart tailscaled
sleep 1
tailscale netcheck
tailscale status
printf "\nTailscale config script finished.\n"

# Tips:
# - To advertise subnets later:
#   sudo tailscale set --advertise-routes=192.0.2.0/24,198.51.100.0/24
# - To verify DNS/MagicDNS:
#   tailscale status
#   tailscale netcheck