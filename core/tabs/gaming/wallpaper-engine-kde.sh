#!/bin/sh -e

. ../common-script.sh

# Wallpaper Engine for KDE Plasma 6
# Installs catsout's wallpaper-engine-kde-plugin, points it at the Steam
# library that holds Wallpaper Engine (app 431960) and optionally enables it
# on every desktop. Upstream is archived (moved to waywallen), so only Arch
# repos (CachyOS, Chaotic-AUR) and the AUR still ship it.

PLUGIN_PKG="plasma6-wallpapers-wallpaper-engine-git"
PLUGIN_ID="com.github.catsout.wallpaperEngineKde"
WE_APPID="431960"

checkPlasma() {
    if ! command_exists plasmashell; then
        printf "%b\n" "${RED}KDE Plasma not found. This plugin only works on Plasma 6.${RC}"
        exit 1
    fi
    if [ "$PACKAGER" != "pacman" ]; then
        printf "%b\n" "${RED}${PLUGIN_PKG} is only packaged for Arch-based distros.${RC}"
        printf "%b\n" "${YELLOW}Upstream is archived; see https://github.com/waywallen/waywallen for its successor.${RC}"
        exit 1
    fi
}

# Run a Plasma desktop script in the running plasmashell; prints its output.
plasmaScript() {
    for qdbus_bin in qdbus6 qdbus; do
        if command_exists "$qdbus_bin"; then
            "$qdbus_bin" org.kde.plasmashell /PlasmaShell org.kde.PlasmaShell.evaluateScript "$1"
            return
        fi
    done
    printf "%b\n" "${YELLOW}qdbus not found (package qt6-tools). Skipping desktop configuration.${RC}"
    return 1
}

# Print the Steam library root that contains Wallpaper Engine, if any.
findWallpaperEngineLibrary() {
    for steam_root in "$HOME/.local/share/Steam" "$HOME/.steam/steam" "$HOME/.var/app/com.valvesoftware.Steam/.local/share/Steam"; do
        vdf="$steam_root/steamapps/libraryfolders.vdf"
        [ -f "$vdf" ] || continue
        sed -n 's/^[[:space:]]*"path"[[:space:]]*"\(.*\)"/\1/p' "$vdf"
    done | sort -u | while IFS= read -r library; do
        if [ -f "$library/steamapps/appmanifest_${WE_APPID}.acf" ]; then
            printf "%s\n" "$library"
            break
        fi
    done
}

installPlugin() {
    if pacman -Q "$PLUGIN_PKG" >/dev/null 2>&1; then
        printf "%b\n" "${GREEN}${PLUGIN_PKG} is already installed.${RC}"
    elif pacman -Si "$PLUGIN_PKG" >/dev/null 2>&1; then
        printf "%b\n" "${YELLOW}Installing ${PLUGIN_PKG} from the repos...${RC}"
        "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm "$PLUGIN_PKG"
    else
        printf "%b\n" "${YELLOW}Building ${PLUGIN_PKG} from the AUR (this takes a few minutes)...${RC}"
        "$AUR_HELPER" -S --needed --noconfirm "$PLUGIN_PKG"
    fi

    # Optional mpv video backend, selectable in the plugin settings
    "$ESCALATION_TOOL" "$PACKAGER" -S --needed --noconfirm mpv

    if [ ! -d "/usr/share/plasma/wallpapers/$PLUGIN_ID" ]; then
        printf "%b\n" "${RED}Error: Plugin files not found after installation.${RC}"
        exit 1
    fi
    printf "%b\n" "${GREEN}Wallpaper Engine plugin installed.${RC}"
}

configureDesktops() {
    library=$(findWallpaperEngineLibrary)
    if [ -z "$library" ]; then
        printf "%b\n" "${YELLOW}Wallpaper Engine (Steam app ${WE_APPID}) is not installed in any Steam library.${RC}"
        printf "%b\n" "${YELLOW}Buy and install it in Steam (no need to run it), subscribe to wallpapers on its Workshop,${RC}"
        printf "%b\n" "${YELLOW}then run this script again or set the Steam library path in the wallpaper settings.${RC}"
        return 0
    fi
    printf "%b\n" "${CYAN}Wallpaper Engine found in ${library}${RC}"
    if [ ! -d "$library/steamapps/common/wallpaper_engine/assets" ]; then
        printf "%b\n" "${YELLOW}Warning: wallpaper_engine/assets is missing. Scene wallpapers need it; verify the game files in Steam.${RC}"
    fi

    printf "%b" "Set Wallpaper Engine as the wallpaper on all desktops now? [y/N]: "
    read -r enable_choice
    case "$enable_choice" in
        y|Y) set_plugin='d.wallpaperPlugin = plugin;' ;;
        *) set_plugin='' ;;
    esac

    # The plugin needs the Steam library root to find the Workshop folder.
    plasmaScript "
        var plugin = \"$PLUGIN_ID\";
        desktops().forEach(function (d) {
            $set_plugin
            d.currentConfigGroup = [\"Wallpaper\", plugin, \"General\"];
            d.writeConfig(\"SteamLibraryPath\", \"file://$library\");
        });" || return 0

    printf "%b\n" "${GREEN}Steam library path saved for all desktops.${RC}"
    printf "%b\n" "${CYAN}Pick a wallpaper in: Desktop right-click > Configure Desktop and Wallpaper > Wallpaper Engine.${RC}"
}

uninstallPlugin() {
    if ! pacman -Q "$PLUGIN_PKG" >/dev/null 2>&1; then
        printf "%b\n" "${CYAN}${PLUGIN_PKG} is not installed.${RC}"
        return 0
    fi

    # Switch affected desktops back to a plain image first, or they turn black.
    plasmaScript "
        desktops().forEach(function (d) {
            if (d.wallpaperPlugin == \"$PLUGIN_ID\") {
                d.wallpaperPlugin = \"org.kde.image\";
            }
        });" || true

    printf "%b\n" "${YELLOW}Removing ${PLUGIN_PKG}...${RC}"
    "$ESCALATION_TOOL" "$PACKAGER" -Rns --noconfirm "$PLUGIN_PKG"
    printf "%b\n" "${GREEN}Wallpaper Engine plugin removed. Wallpaper Engine itself stays installed in Steam.${RC}"
}

main() {
    printf "%b\n" "${YELLOW}Choose action for the Wallpaper Engine KDE plugin:${RC}"
    printf "%b\n" "1. ${YELLOW}Install${RC}"
    printf "%b\n" "2. ${YELLOW}Uninstall${RC}"
    printf "%b\n" "3. ${YELLOW}Abort${RC}"
    printf "%b" "Enter your choice [1-3]: "
    read -r action_choice

    case "$action_choice" in
        1) installPlugin; configureDesktops ;;
        2) uninstallPlugin ;;
        3) printf "%b\n" "${CYAN}Aborted.${RC}" ; exit 0 ;;
        *) printf "%b\n" "${RED}Invalid action choice.${RC}" ; exit 1 ;;
    esac
}

checkEnv
checkPlasma
main
