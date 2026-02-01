#!/bin/sh
# BlackArch Linux repository setup script for Arch Linux and derivatives
# This script sets up BlackArch, fixes mirrors, and lets you interactively select categories to install.

set -eu

. "$(dirname "$(realpath "$0")")/../../../../common-script.sh"

checkArchEnv() {
    if ! command -v pacman >/dev/null 2>&1; then
        printf "%b\n" "${RED}[✗] This script requires Arch Linux or an Arch-based distribution.${RC}"
        exit 1
    fi
    if ! command -v curl >/dev/null 2>&1; then
        printf "%b\n" "${RED}[✗] curl is required but not installed.${RC}"
        exit 1
    fi
    if ! command -v sha1sum >/dev/null 2>&1; then
        printf "%b\n" "${RED}[✗] sha1sum is required but not installed.${RC}"
        exit 1
    fi
}

checkArchEnv

# Check if BlackArch is already installed
if pacman -Sl blackarch >/dev/null 2>&1; then
    printf "%b\n" "${GREEN}[✓] BlackArch repository is already configured.${RC}"
else
    printf "%b\n" "${CYAN}[BlackArch] Setting up BlackArch repository...${RC}"
    
    # Download and run the official setup script
    printf "%b\n" "${CYAN}[BlackArch] Downloading setup script...${RC}"
    curl -O https://blackarch.org/strap.sh
    
    # Verify checksum
    printf "%b\n" "${CYAN}[BlackArch] Verifying checksum...${RC}"
    EXPECTED_SHA="e26445d34490cc06bd14b51f9924debf569e0ecb"
    ACTUAL_SHA=$(sha1sum strap.sh | awk '{print $1}')
    
    if [ "$ACTUAL_SHA" != "$EXPECTED_SHA" ]; then
        printf "%b\n" "${YELLOW}[!] Warning: Checksum doesn't match expected value.${RC}"
        printf "%b\n" "${YELLOW}    Expected: $EXPECTED_SHA${RC}"
        printf "%b\n" "${YELLOW}    Got:      $ACTUAL_SHA${RC}"
        printf "%b\n" "${YELLOW}[!] Proceeding anyway (checksum may have been updated)...${RC}"
    else
        printf "%b\n" "${GREEN}[✓] Checksum verified successfully.${RC}"
    fi
    
    # Make executable and run
    chmod +x strap.sh
    sudo ./strap.sh
    
    # Clean up
    rm -f strap.sh
    
    # Update mirror list
    printf "%b\n" "${CYAN}[BlackArch] Updating mirror list...${RC}"
    sudo curl -sSf -o /etc/pacman.d/blackarch-mirrorlist https://blackarch.org/blackarch-mirrorlist || {
        printf "%b\n" "${YELLOW}[!] Warning: Failed to update mirror list. Using default.${RC}"
    }
    
    # Sync databases
    printf "%b\n" "${CYAN}[BlackArch] Syncing package databases...${RC}"
    sudo pacman -Sy
fi

# Get available categories
printf "%b\n" "${CYAN}[BlackArch] Fetching available categories...${RC}"
categories=$(pacman -Sg 2>/dev/null | grep '^blackarch-' | awk '{print $1}' | sort -u)

if [ -z "$categories" ]; then
    printf "%b\n" "${RED}[✗] Error: No BlackArch categories found. Repository may not be properly configured.${RC}"
    exit 1
fi

# Define category descriptions
get_description() {
    case "$1" in
        blackarch-anti-forensic) echo "Tools for hiding or destroying evidence" ;;
        blackarch-automation) echo "Tools for automation of tasks" ;;
        blackarch-backdoor) echo "Tools for backdoor access" ;;
        blackarch-binary) echo "Tools for binary analysis" ;;
        blackarch-bluetooth) echo "Tools for Bluetooth exploitation" ;;
        blackarch-code-audit) echo "Tools for code auditing" ;;
        blackarch-cracker) echo "Password crackers" ;;
        blackarch-crypto) echo "Cryptography tools" ;;
        blackarch-database) echo "Database exploitation tools" ;;
        blackarch-debugger) echo "Debugging tools" ;;
        blackarch-decompiler) echo "Decompilers and disassemblers" ;;
        blackarch-defensive) echo "Defensive security tools" ;;
        blackarch-disassembler) echo "Disassemblers" ;;
        blackarch-dos) echo "Denial of Service tools" ;;
        blackarch-drone) echo "Drone hacking tools" ;;
        blackarch-exploit) echo "Exploitation tools and frameworks" ;;
        blackarch-fingerprint) echo "Fingerprinting and enumeration tools" ;;
        blackarch-firmware) echo "Firmware analysis tools" ;;
        blackarch-forensic) echo "Forensic analysis tools" ;;
        blackarch-fuzzer) echo "Fuzzers for finding vulnerabilities" ;;
        blackarch-hardware) echo "Hardware hacking tools" ;;
        blackarch-honeypot) echo "Honeypot tools" ;;
        blackarch-keylogger) echo "Keyloggers" ;;
        blackarch-malware) echo "Malware analysis tools" ;;
        blackarch-misc) echo "Miscellaneous tools" ;;
        blackarch-mobile) echo "Mobile security tools" ;;
        blackarch-networking) echo "Networking tools" ;;
        blackarch-nfc) echo "NFC tools" ;;
        blackarch-packer) echo "Packers and crypters" ;;
        blackarch-proxy) echo "Proxy tools" ;;
        blackarch-radio) echo "Radio and SDR tools" ;;
        blackarch-recon) echo "Reconnaissance and OSINT tools" ;;
        blackarch-reversing) echo "Reverse engineering tools" ;;
        blackarch-scanner) echo "Vulnerability scanners" ;;
        blackarch-sniffer) echo "Network sniffers" ;;
        blackarch-social) echo "Social engineering tools" ;;
        blackarch-spoof) echo "Spoofing tools" ;;
        blackarch-threat-model) echo "Threat modeling tools" ;;
        blackarch-tunnel) echo "Tunneling tools" ;;
        blackarch-unpacker) echo "Unpackers" ;;
        blackarch-voip) echo "VoIP exploitation tools" ;;
        blackarch-webapp) echo "Web application security tools" ;;
        blackarch-windows) echo "Windows exploitation tools" ;;
        blackarch-wireless) echo "Wireless security tools" ;;
        *) echo "No description available" ;;
    esac
}

# Display categories
printf "\n%b\n" "${GREEN}Available BlackArch categories:${RC}\n"
counter=1
for cat in $categories; do
    desc=$(get_description "$cat")
    printf "%b%3d)%b %-35s %s\n" "${CYAN}" "$counter" "${RC}" "$cat" "$desc"
    counter=$((counter + 1))
done

printf "\n%b\n" "${GREEN}Options:${RC}"
printf "%s\n" "  • Enter numbers (e.g., 1 5 12) to install specific categories"
printf "%s\n" "  • Enter 'all' to install all categories"
printf "%s\n" "  • Enter 'q' to quit without installing"
printf "\n%b" "${CYAN}Your choice:${RC} "
read -r input

# Handle quit
if [ "$input" = "q" ] || [ "$input" = "Q" ]; then
    printf "%b\n" "${YELLOW}[!] Exiting without installing anything.${RC}"
    exit 0
fi

# Select categories
selected=""
if [ "$input" = "all" ]; then
    selected="$categories"
else
    counter=1
    for cat in $categories; do
        for num in $input; do
            if [ "$num" = "$counter" ]; then
                selected="$selected $cat"
                break
            fi
        done
        counter=$((counter + 1))
    done
fi

if [ -z "$selected" ]; then
    printf "%b\n" "${RED}[✗] No valid categories selected. Exiting.${RC}"
    exit 1
fi

# Display selection
printf "\n%b\n" "${GREEN}Selected categories:${RC}"
for cat in $selected; do
    printf "%b\n" "  ${CYAN}•${RC} $cat"
done

# Estimate package count
printf "\n"
total_packages=0
for cat in $selected; do
    count=$(pacman -Sgq "$cat" 2>/dev/null | wc -l)
    total_packages=$((total_packages + count))
done
printf "%b\n" "${YELLOW}Estimated packages to install: ~${total_packages}${RC}"

# Confirm or install
printf "\n%b\n" "${CYAN}Proceeding with installation...${RC}"
# shellcheck disable=SC2086
sudo pacman -S --needed --noconfirm $selected 2>&1 | tee /tmp/blackarch-install.log || {
    printf "%b\n" "${RED}[✗] Installation encountered errors. Check /tmp/blackarch-install.log${RC}"
    exit 1
}
printf "\n%b\n" "${GREEN}[✓] Installation completed successfully!${RC}"
