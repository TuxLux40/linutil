#!/bin/sh
set -e

# Minimal Tailscale install + setup

# 1) Install Tailscale via official script if missing
if ! command -v tailscale >/dev/null 2>&1; then
	curl -fsSL https://tailscale.com/install.sh | sh
fi

# 2) Enable and start tailscaled (best-effort if systemd exists)
if command -v systemctl >/dev/null 2>&1; then
	sudo systemctl enable --now tailscaled
fi

# 3) Set operator (best-effort)
sudo tailscale set --operator="$USER" || true

# 4) Enable OpenSSH (unit name varies by distro; best-effort)
if command -v systemctl >/dev/null 2>&1; then
	sudo systemctl enable --now ssh.service 2>/dev/null || \
	sudo systemctl enable --now sshd.service 2>/dev/null || true
fi

# 5) Enable IP forwarding (persist if possible)
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
if [ -n "${TS_AUTHKEY:-}" ]; then
	sudo tailscale up --ssh --accept-routes --authkey="$TS_AUTHKEY"
else
	sudo tailscale up --ssh --accept-routes || true
fi

# Tips:
# - To advertise subnets later:
#   sudo tailscale set --advertise-routes=192.0.2.0/24,198.51.100.0/24