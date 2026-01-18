#!/bin/sh -e

. ../common-script.sh

# Theme URLs - from official repositories
# RedmondX Icons: https://github.com/yeyushengfan258/Redmond-Icon-Theme
# Alternative sources: AUR, Pling.com
REDMOND_X_ICON_URL="https://github.com/yeyushengfan258/Redmond-Icon-Theme/releases/download/6.2/redmondx-icon-theme-6.2-1-any.pkg.tar.zst"
REDMOND_X_ICON_ALT="https://github.com/yeyushengfan258/Redmond-Icon-Theme/archive/refs/tags/6.2.tar.gz"

# Willow Dark Blur Window Decorations: https://github.com/Nitrux/aurorae-themes
# These are Aurorae decoration themes for KDE Plasma
WILLOW_DARK_BLUR_URL="https://github.com/Nitrux/aurorae-themes/archive/refs/heads/main.tar.gz"

install_dependencies() {
    printf "%b\n" "${YELLOW}Installing required dependencies...${RC}"
    case "$PACKAGER" in
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" install -y wget tar gzip curl
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install wget tar gzip curl
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" install -y wget tar gzip curl
            ;;
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm wget tar gzip curl
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy wget tar gzip curl
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: ""$PACKAGER""${RC}"
            exit 1
            ;;
    esac
}

install_icon_pack() {
    printf "%b\n" "${YELLOW}Installing RedmondX icon pack...${RC}"
    local temp_dir="/tmp/redmond_icons_$$"
    mkdir -p "$temp_dir"
    mkdir -p "$HOME/.local/share/icons"
    
    # Try primary source first
    if wget -q -O "$temp_dir/redmond.tar.zst" "$REDMOND_X_ICON_URL" 2>/dev/null; then
        tar --zstd -xf "$temp_dir/redmond.tar.zst" -C "$temp_dir" 2>/dev/null
        find "$temp_dir" -type d -name "redmond*" -exec cp -r {} "$HOME/.local/share/icons/" \;
        printf "%b\n" "${GREEN}RedmondX icon pack installed successfully.${RC}"
    # Try alternative format
    elif wget -q -O "$temp_dir/redmond.tar.gz" "$REDMOND_X_ICON_ALT" 2>/dev/null; then
        tar -xzf "$temp_dir/redmond.tar.gz" -C "$temp_dir"
        if [ -d "$temp_dir/Redmond-Icon-Theme-6.2" ]; then
            cp -r "$temp_dir/Redmond-Icon-Theme-6.2"/* "$HOME/.local/share/icons/"
            printf "%b\n" "${GREEN}RedmondX icon pack installed successfully.${RC}"
        fi
    else
        printf "%b\n" "${YELLOW}Could not download RedmondX automatically. Install manually:${RC}"
        printf "%b\n" "${YELLOW}https://github.com/yeyushengfan258/Redmond-Icon-Theme/releases${RC}"
    fi
    rm -rf "$temp_dir"
}

install_window_decorations() {
    printf "%b\n" "${YELLOW}Installing Willow Dark Blur window decorations...${RC}"
    local temp_dir="/tmp/willow_decorations_$$"
    mkdir -p "$temp_dir"
    mkdir -p "$HOME/.local/share/aurorae/themes"
    
    if wget -q -O "$temp_dir/willow.tar.gz" "$WILLOW_DARK_BLUR_URL" 2>/dev/null; then
        tar -xzf "$temp_dir/willow.tar.gz" -C "$temp_dir"
        # Copy all WillowDark* themes from the extracted directory
        find "$temp_dir" -type d -name "WillowDark*" -exec cp -r {} "$HOME/.local/share/aurorae/themes/" \;
        printf "%b\n" "${GREEN}Willow Dark Blur window decorations installed.${RC}"
    else
        printf "%b\n" "${YELLOW}Could not download Willow Dark Blur. Install manually:${RC}"
        printf "%b\n" "${YELLOW}https://github.com/Nitrux/aurorae-themes${RC}"
    fi
    rm -rf "$temp_dir"
}

install_theme_tools() {
    printf "%b\n" "${YELLOW}Installing theme tools (breeze and dependencies)...${RC}"
    case "$PACKAGER" in
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" install -y breeze-icon-theme breeze kde-style-breeze
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install breeze-icon-theme breeze
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" install -y breeze-icon-theme breeze
            ;;
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm breeze-icons breeze
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy breeze-icons breeze
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: ""$PACKAGER""${RC}"
            exit 1
            ;;
    esac
}

applyTheming() {
    printf "%b\n" "${YELLOW}Applying global theming...${RC}"
    case "$XDG_CURRENT_DESKTOP" in
        KDE)
            kwriteconfig6 --file kdeglobals --group General --key ColorScheme BreezeDark
            kwriteconfig6 --file kdeglobals --group Icons --key Theme breeze-dark
            kwriteconfig6 --file kdeglobals --group KDE --key widgetStyle Breeze
            successOutput
            exit 0
            ;;
        GNOME)
            gsettings set org.gnome.desktop.interface gtk-theme "Windows10"
            gsettings set org.gnome.desktop.interface icon-theme "RedmondX-Dark"
            gsettings set org.gnome.desktop.interface gtk-application-prefer-dark-theme true
            gsettings set org.gnome.desktop.interface cursor-theme "We10XOS-cursors"
            gsettings set org.gnome.desktop.interface font-name "Noto Sans,  10"
            gsettings set org.gnome.desktop.interface monospace-font-name "Hack  10"
            successOutput
            exit 0
            ;;
        *)
            return
            ;;
    esac
}

configure_kde_decorations() {
    printf "%b\n" "${YELLOW}Configuring KDE window decorations...${RC}"
    mkdir -p "$HOME/.config"
    
    # Set window decoration theme to Willow Dark Blur
    cat <<EOF >> "$HOME/.config/kdeglobals"

[org.kde.kdecoration2]
BorderSize=NoSides
BorderSizeAuto=false
library=org.kde.kwin.aurorae
theme=__aurorae__svg__WillowDarkBlur
EOF
    printf "%b\n" "${GREEN}KDE window decorations configured.${RC}"
}

configure_kwin_effects() {
    printf "%b\n" "${YELLOW}Configuring KWin effects (blur)...${RC}"
    
    # Configure blur effect
    mkdir -p "$HOME/.config"
    cat <<EOF >> "$HOME/.config/kwinrc"

[Effect-blur]
BlurStrength=10
NoiseStrength=7

[Plugins]
blurEnabled=true
translucencyEnabled=true
EOF
    printf "%b\n" "${GREEN}KWin blur effects configured.${RC}"
}

configure_plasma_panel() {
    printf "%b\n" "${YELLOW}Configuring Plasma panel...${RC}"
    
    # Configure panel with custom settings
    mkdir -p "$HOME/.config"
    cat <<EOF >> "$HOME/.config/plasmashellrc"

[PlasmaViews][Panel 2]
floating=1

[PlasmaViews][Panel 2][Defaults]
thickness=44

[PlasmaViews][Panel 23]
floating=1
panelOpacity=2

[PlasmaViews][Panel 23][Defaults]
thickness=34
EOF
    printf "%b\n" "${GREEN}Plasma panel configured.${RC}"
}

configure_gtk() {
    printf "%b\n" "${YELLOW}Configuring GTK...${RC}"
    mkdir -p "$HOME/.config/gtk-3.0"
    cat <<EOF > "$HOME/.config/gtk-3.0/settings.ini"
[Settings]
gtk-application-prefer-dark-theme=true
gtk-button-images=true
gtk-cursor-blink=true
gtk-cursor-blink-time=1000
gtk-cursor-theme-name=We10XOS-cursors
gtk-cursor-theme-size=30
gtk-decoration-layout=icon:minimize,maximize,close
gtk-enable-animations=true
gtk-font-name=Noto Sans,  10
gtk-icon-theme-name=RedmondX-Dark
gtk-menu-images=true
gtk-modules=colorreload-gtk-module:window-decorations-gtk-module:appmenu-gtk-module
gtk-primary-button-warps-slider=true
gtk-shell-shows-menubar=1
gtk-sound-theme-name=ocean
gtk-theme-name=Windows10
gtk-toolbar-style=3
gtk-xft-dpi=98304
EOF
    printf "%b\n" "${GREEN}GTK configured successfully.${RC}"
}



successOutput() {
    printf "%b\n" "${GREEN}Global theming applied successfully.${RC}"
}

checkEnv
checkEscalationTool
install_dependencies
install_theme_tools
install_icon_pack
install_window_decorations
applyTheming
configure_kde_decorations
configure_kwin_effects
configure_plasma_panel
configure_gtk
successOutput