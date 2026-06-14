#!/bin/sh -e

. ../../common-script.sh

configureShaderCache() {
    if grep -q "AMD_VULKAN_ICD=RADV" /etc/environment 2>/dev/null; then
        printf "%b\n" "${YELLOW}AMD shader cache configuration already present in /etc/environment.${RC}"
        return
    fi

    BACKUP="/etc/environment.backup.$(date +%Y%m%d_%H%M%S)"
    printf "%b\n" "${YELLOW}Backing up /etc/environment to ${BACKUP}...${RC}"
    "$ESCALATION_TOOL" cp /etc/environment "$BACKUP"

    printf "%b\n" "${YELLOW}Adding AMD Vulkan and Mesa shader cache settings to /etc/environment...${RC}"
    printf '%s\n' \
        "" \
        "# Enforces RADV Vulkan implementation" \
        "AMD_VULKAN_ICD=RADV" \
        "" \
        "# Increase AMD shader cache size to 12GB" \
        "MESA_SHADER_CACHE_MAX_SIZE=12G" \
        | "$ESCALATION_TOOL" tee -a /etc/environment > /dev/null

    printf "%b\n" "${GREEN}Done. Log out and back in (or reboot) for changes to take effect.${RC}"
}

checkEnv
checkEscalationTool
configureShaderCache
