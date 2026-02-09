#!/bin/sh -e

. ../common-script.sh

THEME_LOOK_AND_FEEL="com.github.yeyushengfan258.Win11OS-dark"
THEME_COLOR_SCHEME="WillowDarkBlur"
THEME_ICON="RedmondX-Dark"
THEME_CURSOR="We10XOS-cursors"
THEME_GTK="Windows-10-Dark-3.2.1-dark"

install_git() {
    if command -v git >/dev/null 2>&1; then
        return 0
    fi

    printf "%b\n" "${YELLOW}Installing git...${RC}"
    case "$PACKAGER" in
        apt-get|nala)
            "$ESCALATION_TOOL" "$PACKAGER" install -y git
            ;;
        zypper)
            "$ESCALATION_TOOL" "$PACKAGER" --non-interactive install git
            ;;
        dnf)
            "$ESCALATION_TOOL" "$PACKAGER" install -y git
            ;;
        pacman)
            "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm git
            ;;
        xbps-install)
            "$ESCALATION_TOOL" "$PACKAGER" -Sy git
            ;;
        *)
            printf "%b\n" "${RED}Unsupported package manager: $PACKAGER${RC}"
            return 1
            ;;
    esac
}

install_theme_assets() {
    install_git || return 1

    TEMP_DIR=$(mktemp -d)
    cd "$TEMP_DIR" || return 1

    printf "%b\n" "${YELLOW}Cloning Win11-icon-theme...${RC}"
    if git clone --depth=1 https://github.com/yeyushengfan258/Win11-icon-theme.git; then
        cd Win11-icon-theme || return 1
        chmod +x install.sh
        ./install.sh -d "$HOME/.local/share/icons" -n Win11 -t yellow
        cd "$TEMP_DIR" || return 1
    fi

    printf "%b\n" "${YELLOW}Cloning RedmondX-icon-theme...${RC}"
    if git clone --depth=1 https://github.com/mjkim0727/RedmondX-icon-theme.git; then
        mkdir -p "$HOME/.local/share/icons/RedmondX-Dark"
        cp -r RedmondX-icon-theme/src/* "$HOME/.local/share/icons/RedmondX-Dark/" 2>/dev/null
        cp -r RedmondX-icon-theme/symlinks/* "$HOME/.local/share/icons/RedmondX-Dark/" 2>/dev/null
    fi

    printf "%b\n" "${YELLOW}Cloning willow-theme...${RC}"
    if git clone --depth=1 https://github.com/doncsugar/willow-theme.git; then
        cd willow-theme || return 1
        
        mkdir -p "$HOME/.local/share/plasma/look-and-feel"
        mkdir -p "$HOME/.local/share/color-schemes"
        mkdir -p "$HOME/.local/share/aurorae/themes"
        mkdir -p "$HOME/.local/share/plasma/desktoptheme"
        
        cp -r global-themes/* "$HOME/.local/share/plasma/look-and-feel/" 2>/dev/null
        cp -r color-schemes/* "$HOME/.local/share/color-schemes/" 2>/dev/null
        cp -r aurorae-themes/* "$HOME/.local/share/aurorae/themes/" 2>/dev/null
        cp -r plasma-style/* "$HOME/.local/share/plasma/desktoptheme/" 2>/dev/null
        
        cd "$TEMP_DIR" || return 1
    fi

    cd "$HOME" || return 1
    rm -rf "$TEMP_DIR"
    
    printf "%b\n" "${GREEN}Theme installation completed.${RC}"
}

asset_missing() {
    if test -e "$1"; then
        return 1
    fi
    case "$1" in
        "$HOME/.local/share/"*)
            if test -e "/usr/share/${1#$HOME/.local/share/}"; then
                return 1
            fi
            ;;
    esac
    return 0
}

ensure_assets() {
    missing_any=0

    if asset_missing "$HOME/.local/share/plasma/look-and-feel/$THEME_LOOK_AND_FEEL"; then
        printf "%b\n" "${YELLOW}Missing KDE Look-and-Feel: $THEME_LOOK_AND_FEEL${RC}"
        missing_any=1
    fi

    if asset_missing "$HOME/.local/share/color-schemes/${THEME_COLOR_SCHEME}.colors"; then
        printf "%b\n" "${YELLOW}Missing KDE color scheme: $THEME_COLOR_SCHEME${RC}"
        missing_any=1
    fi

    if asset_missing "$HOME/.local/share/icons/$THEME_ICON"; then
        printf "%b\n" "${YELLOW}Missing icon theme: $THEME_ICON${RC}"
        missing_any=1
    fi

    if asset_missing "$HOME/.local/share/icons/$THEME_CURSOR"; then
        printf "%b\n" "${YELLOW}Missing cursor theme: $THEME_CURSOR${RC}"
        missing_any=1
    fi

    if asset_missing "$HOME/.local/share/themes/$THEME_GTK" && asset_missing "$HOME/.themes/$THEME_GTK" && asset_missing "/usr/share/themes/$THEME_GTK"; then
        printf "%b\n" "${YELLOW}Missing GTK theme: $THEME_GTK${RC}"
        missing_any=1
    fi

    if test "$missing_any" -eq 1; then
        install_theme_assets || return 1
    fi
}

applyTheming() {
    printf "%b\n" "${YELLOW}Applying global theming...${RC}"
    case "$XDG_CURRENT_DESKTOP" in
        KDE)
            lookandfeeltool -a "$THEME_LOOK_AND_FEEL"
            kwriteconfig5 --file kdeglobals --group General --key ColorScheme "$THEME_COLOR_SCHEME"
            kwriteconfig5 --file kdeglobals --group Icons --key Theme "$THEME_ICON"
            kwriteconfig5 --file kcminputrc --group Mouse --key cursorTheme "$THEME_CURSOR"
            return 0
            ;;
        GNOME)
            gsettings set org.gnome.desktop.interface gtk-theme "$THEME_GTK"
            gsettings set org.gnome.desktop.interface icon-theme "$THEME_ICON"
            gsettings set org.gnome.desktop.interface cursor-theme "$THEME_CURSOR"
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

successOutput() {
    printf "%b\n" "${GREEN}Global theming applied successfully.${RC}"
}

checkEnv
checkEscalationTool
ensure_assets

if applyTheming; then
    successOutput
else
    printf "%b\n" "${RED}Unsupported desktop: $XDG_CURRENT_DESKTOP${RC}"
    exit 1
fi