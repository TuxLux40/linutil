#!/bin/sh -e

. ../../common-script.sh

installEmuDeck() {
	printf "%b\n" "${YELLOW}Installing EmuDeck...${RC}"

	if ! command_exists curl; then
		printf "%b\n" "${RED}Error: curl is required but not installed.${RC}"
		exit 1
	fi

	if ! command_exists bash; then
		printf "%b\n" "${RED}Error: bash is required but not installed.${RC}"
		exit 1
	fi

	INSTALL_URL="https://raw.githubusercontent.com/dragoonDorise/EmuDeck/main/install.sh"
	TMP_SCRIPT="$(mktemp)"

	if ! curl -fsSL "$INSTALL_URL" -o "$TMP_SCRIPT"; then
		printf "%b\n" "${RED}Error: Failed to download EmuDeck installer.${RC}"
		rm -f "$TMP_SCRIPT"
		exit 1
	fi

	if bash "$TMP_SCRIPT"; then
		printf "%b\n" "${GREEN}EmuDeck installed successfully.${RC}"
	else
		printf "%b\n" "${RED}Error: EmuDeck installer failed.${RC}"
		rm -f "$TMP_SCRIPT"
		exit 1
	fi

	rm -f "$TMP_SCRIPT"
}

checkEnv
installEmuDeck
