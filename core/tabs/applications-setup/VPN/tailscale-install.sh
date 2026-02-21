#!/bin/bash -e

. ../../common-script.sh
. ../../common-service-script.sh

install_tailscale() {
	if ! command_exists tailscale; then
		printf "%b\n" "${YELLOW}Installing Tailscale...${RC}"
		curl -fsSL https://tailscale.com/install.sh | sh
	else
		printf "%b\n" "${GREEN}Tailscale is already installed.${RC}"
	fi
}

enable_tailscaled() {
	printf "%b\n" "${YELLOW}Enabling tailscaled...${RC}"
	startAndEnableService tailscaled
}

enable_ssh_service() {
	ssh_service=""
	case "$INIT_MANAGER" in
		systemctl)
			if "$ESCALATION_TOOL" "$INIT_MANAGER" list-unit-files --type=service 2>/dev/null | awk '{print $1}' | grep -qx "ssh.service"; then
				ssh_service="ssh"
			elif "$ESCALATION_TOOL" "$INIT_MANAGER" list-unit-files --type=service 2>/dev/null | awk '{print $1}' | grep -qx "sshd.service"; then
				ssh_service="sshd"
			fi
			;;
		rc-service)
			if rc-service -l 2>/dev/null | grep -qx "sshd"; then
				ssh_service="sshd"
			elif rc-service -l 2>/dev/null | grep -qx "ssh"; then
				ssh_service="ssh"
			fi
			;;
		sv)
			if [ -d "/etc/sv/sshd" ] || [ -d "/var/service/sshd" ]; then
				ssh_service="sshd"
			elif [ -d "/etc/sv/ssh" ] || [ -d "/var/service/ssh" ]; then
				ssh_service="ssh"
			fi
			;;
	esac

	if [ -n "$ssh_service" ]; then
		printf "%b\n" "${YELLOW}Enabling SSH service (${ssh_service})...${RC}"
		startAndEnableService "$ssh_service"
	else
		printf "%b\n" "${YELLOW}SSH service not detected; skipping enable step.${RC}"
	fi
}

configure_ip_forwarding() {
	printf "%b\n" "${YELLOW}Configuring IP forwarding...${RC}"
	if [ -d /etc/sysctl.d ]; then
		"$ESCALATION_TOOL" tee /etc/sysctl.d/99-tailscale.conf >/dev/null <<'EOF'
net.ipv4.ip_forward = 1
net.ipv6.conf.all.forwarding = 1
EOF
		"$ESCALATION_TOOL" sysctl -p /etc/sysctl.d/99-tailscale.conf
	else
		"$ESCALATION_TOOL" sysctl -w net.ipv4.ip_forward=1
		"$ESCALATION_TOOL" sysctl -w net.ipv6.conf.all.forwarding=1
	fi
}

bring_tailscale_up() {
	printf "%b\n" "${YELLOW}Bringing Tailscale up...${RC}"
	if [ -n "${TS_AUTHKEY:-}" ]; then
		"$ESCALATION_TOOL" tailscale up --ssh --accept-routes --authkey="$TS_AUTHKEY"
	else
		if ! "$ESCALATION_TOOL" tailscale up --ssh --accept-routes; then
			printf "%b\n" "${YELLOW}Tailscale up did not complete. You can rerun 'tailscale up' interactively.${RC}"
		fi
	fi
}

set_tailscale_operator() {
	printf "%b\n" "${YELLOW}Setting Tailscale operator to ${USER}...${RC}"
	if "$ESCALATION_TOOL" tailscale set --operator="$USER"; then
		printf "%b\n" "${GREEN}Operator set successfully.${RC}"
	else
		printf "%b\n" "${YELLOW}Failed to set operator. Make sure Tailscale is up and authenticated, then rerun 'tailscale set --operator=${USER}'.${RC}"
	fi
}

checkEnv
checkEscalationTool
checkInitManager
checkCommandRequirements "curl"
install_tailscale
enable_tailscaled
enable_ssh_service
configure_ip_forwarding
bring_tailscale_up
set_tailscale_operator

# Tips:
# - To advertise subnets later:
#   sudo tailscale set --advertise-routes=192.0.2.0/24,198.51.100.0/24