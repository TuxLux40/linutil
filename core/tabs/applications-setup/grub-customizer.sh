#!/bin/sh -e

. ../common-script.sh

installGrubCustomizer() {
	if command_exists grub-customizer; then
		printf "%b\n" "${GREEN}Grub Customizer is already installed.${RC}"
		return 0
	fi

	printf "%b\n" "${YELLOW}Installing Grub Customizer...${RC}"

	case "$PACKAGER" in
		apt-get|nala)
			if ! command_exists add-apt-repository; then
				"$ESCALATION_TOOL" "$PACKAGER" install -y software-properties-common
			fi
			"$ESCALATION_TOOL" add-apt-repository -y ppa:trebelnik-stefina/grub-customizer
			"$ESCALATION_TOOL" "$PACKAGER" update
			"$ESCALATION_TOOL" "$PACKAGER" install -y grub-customizer
			;;
		dnf)
			"$ESCALATION_TOOL" "$PACKAGER" install -y grub-customizer
			;;
		pacman)
			"$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm grub-customizer
			;;
		*)
			printf "%b\n" "${RED}Unsupported package manager for Grub Customizer installation.${RC}"
			return 1
			;;
	esac

	printf "%b\n" "${GREEN}Grub Customizer installation completed!${RC}"
}

checkEnv
checkEscalationTool
installGrubCustomizer
