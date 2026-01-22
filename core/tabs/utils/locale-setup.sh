#!/bin/sh -e

. ../common-script.sh

setupLocale() {
    printf "%b\n" "${YELLOW}Setting up locale (English language with German formats & keyboard layout)...${RC}"
    
    # Configure locale settings
    # LANG=en_US.UTF-8 for English UI/menus
    # LC_* variables set to de_DE.UTF-8 for German formats
    printf "%b\n" "${CYAN}Configuring locale environment...${RC}"
    "$ESCALATION_TOOL" tee /etc/environment >/dev/null <<'EOF'
LANG=en_US.UTF-8
LC_TIME=de_DE.UTF-8
LC_NUMERIC=de_DE.UTF-8
LC_MONETARY=de_DE.UTF-8
LC_PAPER=de_DE.UTF-8
LC_MEASUREMENT=de_DE.UTF-8
EOF

    # Generate both locales
    printf "%b\n" "${CYAN}Generating locales...${RC}"
    "$ESCALATION_TOOL" tee /etc/locale.gen >/dev/null <<'EOF'
en_US.UTF-8 UTF-8
de_DE.UTF-8 UTF-8
EOF
    "$ESCALATION_TOOL" locale-gen

    # Set German keyboard layout for console
    printf "%b\n" "${CYAN}Setting keyboard layout to German...${RC}"
    "$ESCALATION_TOOL" tee /etc/vconsole.conf >/dev/null <<'EOF'
KEYMAP=de-latin1
EOF

    # Set German keyboard layout for X11/Wayland
    "$ESCALATION_TOOL" mkdir -p /etc/X11/xorg.conf.d
    "$ESCALATION_TOOL" tee /etc/X11/xorg.conf.d/00-keyboard.conf >/dev/null <<'EOF'
Section "InputClass"
    Identifier "system-keyboard"
    MatchIsKeyboard "on"
    Option "XkbLayout" "de"
    Option "XkbVariant" "nodeadkeys"
EndSection
EOF

    printf "%b\n" "${GREEN}Locale and keyboard layout configured successfully.${RC}"
    printf "%b\n" "${YELLOW}Language: English (en_US)${RC}"
    printf "%b\n" "${YELLOW}Formats: German (de_DE)${RC}"
    printf "%b\n" "${YELLOW}Keyboard: German${RC}"
    printf "%b\n" "${RED}Please restart or log out for changes to take effect.${RC}"
}

checkEnv
checkEscalationTool
setupLocale
