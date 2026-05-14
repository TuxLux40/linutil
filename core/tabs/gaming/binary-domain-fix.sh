#!/bin/sh
# binary-domain-fix.sh
# Fixes Binary Domain (Steam AppID 203750) on Linux/Proton:
#   Step 1 – Install XAudio2 via protontricks (CRI Audio / no-sound fix)
#   Step 2 – Fix GPU GUID: run BinaryDomainConfiguration.exe under Proton so
#             DXVK writes a valid D3D9 adapter GUID, then restore max graphics
#   Step 3 – Patch localconfig.vdf: set launch options and disable Steam Input
#             (fixes gamepad not working in gameplay)
#
# Steps 1 & 2 require Steam to be RUNNING.
# Step 3 requires Steam to be CLOSED.
#
# Source: https://github.com/TuxLux40/gaming-mode-fixes/tree/master/binary-domain

# shellcheck source=core/tabs/common-script.sh
. ../common-script.sh

APP_ID="203750"
GAME_NAME="Binary Domain"
GAME_DIR=""
LOCALCONFIG=""

# ── Helpers ──────────────────────────────────────────────────────────────────

find_game_dir() {
    _default="$HOME/.local/share/Steam/steamapps/common/$GAME_NAME"
    if [ -d "$_default" ]; then
        GAME_DIR="$_default"
        return 0
    fi
    GAME_DIR=$(find "$HOME" /mnt -maxdepth 7 -type d -name "$GAME_NAME" 2>/dev/null | head -1)
    [ -n "$GAME_DIR" ]
}

find_localconfig() {
    # Prefer the account that already has a Binary Domain entry
    for _cfg in "$HOME/.local/share/Steam/userdata"/*/config/localconfig.vdf; do
        [ -f "$_cfg" ] && grep -q '"203750"' "$_cfg" && { LOCALCONFIG="$_cfg"; return 0; }
    done
    # Fall back to any available localconfig
    for _cfg in "$HOME/.local/share/Steam/userdata"/*/config/localconfig.vdf; do
        [ -f "$_cfg" ] && { LOCALCONFIG="$_cfg"; return 0; }
    done
    return 1
}

detect_resolution() {
    _res=$(xrandr 2>/dev/null | awk '/*/{print $1}' | head -1)
    printf "%s" "${_res:-1920x1080}"
}

# ── Prerequisites ─────────────────────────────────────────────────────────────

printf "%b\n" "${YELLOW}Binary Domain – Linux/Proton Fix${RC}"
printf "%b\n" "${CYAN}Steam AppID: $APP_ID${RC}"
printf "%b\n" ""

if ! command_exists python3; then
    printf "%b\n" "${RED}python3 is required but not found. Please install python3.${RC}"
    exit 1
fi

if ! find_game_dir; then
    printf "%b\n" "${RED}Binary Domain installation not found.${RC}"
    printf "%b\n" "${YELLOW}Install the game via Steam first, then re-run this script.${RC}"
    exit 1
fi

printf "%b\n" "${GREEN}Game found: $GAME_DIR${RC}"

# ── Step 1: Install XAudio2 ───────────────────────────────────────────────────

printf "%b\n" ""
printf "%b\n" "${YELLOW}=== Step 1: Install XAudio2 (sound fix) ===${RC}"
printf "%b\n" "Binary Domain uses CRI Audio / XAudio2.7. This installs the native"
printf "%b\n" "Microsoft DLLs into the Proton prefix so in-game audio works."
printf "%b\n" ""

if ! command_exists protontricks; then
    printf "%b\n" "${RED}protontricks not found. Install it and re-run.${RC}"
    printf "%b\n" "${CYAN}  Arch/CachyOS: paru -S protontricks${RC}"
    printf "%b\n" "${CYAN}  Flatpak: flatpak install flathub com.github.Matoking.protontricks${RC}"
    exit 1
fi

if ! pgrep -x steam > /dev/null 2>&1; then
    printf "%b\n" "${RED}Steam must be RUNNING for Steps 1 and 2.${RC}"
    printf "%b\n" "${YELLOW}Start Steam, then re-run this script.${RC}"
    exit 1
fi

printf "%b\n" "${YELLOW}Running: protontricks $APP_ID xact${RC}"
printf "%b\n" "${CYAN}A Wine installer dialog will appear – click through to install.${RC}"
printf "%b\n" ""
protontricks "$APP_ID" xact || {
    printf "%b\n" "${RED}protontricks xact failed. Check the output above.${RC}"
    exit 1
}
printf "%b\n" "${GREEN}Step 1 complete.${RC}"

# ── Step 2: Fix GPU GUID ──────────────────────────────────────────────────────

printf "%b\n" ""
printf "%b\n" "${YELLOW}=== Step 2: Fix GPU GUID (graphics device error fix) ===${RC}"
printf "%b\n" "Launches BinaryDomainConfiguration.exe under Proton so DXVK writes"
printf "%b\n" "a valid D3D9 adapter GUID into UserCFG.txt."
printf "%b\n" ""

if ! command_exists protontricks-launch; then
    printf "%b\n" "${RED}protontricks-launch not found (should be bundled with protontricks).${RC}"
    exit 1
fi

CFG="$GAME_DIR/savedata/UserCFG.txt"
if [ ! -f "$CFG" ]; then
    printf "%b\n" "${RED}UserCFG.txt not found at: $CFG${RC}"
    printf "%b\n" "${YELLOW}Launch the game once (even if it crashes) to create UserCFG.txt, then re-run.${RC}"
    exit 1
fi

BACKUP_GUID="${CFG}.bak-$(date +%Y%m%d%H%M%S)"
cp "$CFG" "$BACKUP_GUID"
printf "%b\n" "${GREEN}Backed up UserCFG.txt → $BACKUP_GUID${RC}"

printf "%b\n" ""
printf "%b\n" "${YELLOW}Launching BinaryDomainConfiguration.exe...${RC}"
printf "%b\n" "${CYAN}  1. Select your GPU from the adapter dropdown${RC}"
printf "%b\n" "${CYAN}  2. Click OK or Apply${RC}"
printf "%b\n" "${CYAN}  3. Close the window${RC}"
printf "%b\n" ""
protontricks-launch --appid "$APP_ID" "$GAME_DIR/BinaryDomainConfiguration.exe"

printf "%b\n" "${YELLOW}Restoring max graphics settings (config tool resets them to low)...${RC}"
_res=$(detect_resolution)
_res_w=$(printf "%s" "$_res" | cut -dx -f1)
_res_h=$(printf "%s" "$_res" | cut -dx -f2 | cut -d+ -f1)

python3 - "$CFG" "$_res_w" "$_res_h" <<'PYEOF'
import sys, re

path  = sys.argv[1]
res_w = sys.argv[2]
res_h = sys.argv[3]

with open(path, 'r', encoding='utf-8') as f:
    content = f.read()

guid_match = re.search(r'guid="([^"]+)"', content)
if guid_match:
    guid = guid_match.group(1)
    if guid == "00000000-0000-0000-0000-000000000000":
        print("WARNING: GUID is still all-zeros — did you select a GPU and click OK?", file=sys.stderr)
        print("         Re-run Step 2 if the 'graphics device invalid' error persists.", file=sys.stderr)
    else:
        print(f"  GUID written: {guid}")
else:
    print("WARNING: guid= attribute not found in UserCFG.txt", file=sys.stderr)

options_max = (
    '<options aa="2" vsync="1" windowed="0" motionblur="1" ssao="1" shadow="1" '
    'reflection="1" inversion="0" control_layout="0" vibration="1" '
    'fov_norm="38" fov_aim="26" volume="100" voice_language="0" />'
)
content, n_opts = re.subn(r'<options\b[^/]*/>', options_max, content)
if n_opts == 0:
    content, _ = re.subn(r'<options\b.*?>', options_max, content, flags=re.DOTALL)

res_tag = f'<resolution width="{res_w}" height="{res_h}" refresh="60" />'
content, _ = re.subn(r'<resolution\b[^/]*/>', res_tag, content)

with open(path, 'w', encoding='utf-8') as f:
    f.write(content)

print(f"  Options set to max (aa=2, all effects on)")
print(f"  Resolution set to {res_w}x{res_h} @ 60 Hz")
PYEOF

printf "%b\n" "${GREEN}Step 2 complete.${RC}"

# ── Step 3: Patch localconfig.vdf ────────────────────────────────────────────

printf "%b\n" ""
printf "%b\n" "${YELLOW}=== Step 3: Steam Launch Options & Gamepad Fix ===${RC}"
printf "%b\n" "Sets launch options (audio DLL override, disable gamescope WSI) and"
printf "%b\n" "disables Steam Input so the gamepad works in gameplay."
printf "%b\n" ""
printf "%b\n" "${YELLOW}Close Steam completely, then press Enter to continue...${RC}"
read -r _unused

# Wait up to 60 s for Steam to exit
_waited=0
while pgrep -x steam > /dev/null 2>&1; do
    if [ "$_waited" -ge 60 ]; then
        printf "%b\n" "${RED}Steam is still running after 60 s. Close it manually and re-run.${RC}"
        exit 1
    fi
    printf "\r${YELLOW}Waiting for Steam to close... %ds${RC}" "$_waited"
    sleep 2
    _waited=$((_waited + 2))
done
printf "\n"

if ! find_localconfig; then
    printf "%b\n" "${RED}Could not find localconfig.vdf in any Steam userdata directory.${RC}"
    exit 1
fi

printf "%b\n" "${GREEN}Using: $LOCALCONFIG${RC}"
BACKUP_LC="${LOCALCONFIG}.bak-$(date +%Y%m%d%H%M%S)"
cp "$LOCALCONFIG" "$BACKUP_LC"
printf "%b\n" "${GREEN}Backed up localconfig.vdf → $BACKUP_LC${RC}"

NEW_LAUNCH_OPTS='DISABLE_GAMESCOPE_WSI=1 PULSE_LATENCY_MSEC=60 WINEDLLOVERRIDES=xaudio2_7=n,b %command%'

python3 - "$LOCALCONFIG" "$APP_ID" "$NEW_LAUNCH_OPTS" <<'PYEOF'
import sys, re

localconfig_path = sys.argv[1]
app_id           = sys.argv[2]
new_launch_opts  = sys.argv[3]

with open(localconfig_path, 'r', encoding='utf-8') as f:
    lines = f.readlines()

# Walk the VDF line-by-line to find the "203750" game-data block.
# (There are other "203750" occurrences as token-hash keys; we want the
# one followed by a bare "{" and containing "LastPlayed".)
state          = 'searching'
depth          = 0
target_start_i = -1
launch_opts_i  = -1
steam_input_i  = -1
block_end_i    = -1

i = 0
while i < len(lines):
    line     = lines[i]
    stripped = line.strip()

    if state == 'searching':
        if re.match(r'^\s+"' + re.escape(app_id) + r'"\s*$', line):
            state = 'found_id'
            target_start_i = i

    elif state == 'found_id':
        if stripped == '{':
            state = 'in_block'
            depth = 1
        elif stripped != '':
            state = 'searching'
            target_start_i = -1

    elif state == 'in_block':
        if stripped == '{':
            depth += 1
        elif stripped == '}':
            depth -= 1
            if depth == 0:
                block_end_i = i
                state = 'done'
                break
        if depth == 1:
            if '"LaunchOptions"' in stripped:
                launch_opts_i = i
            if '"SteamInput"' in stripped:
                steam_input_i = i

    i += 1

if state != 'done' or block_end_i == -1:
    print(f"ERROR: Could not locate app {app_id} block in localconfig.vdf", file=sys.stderr)
    print( "       Launch Binary Domain via Steam at least once, then re-run.", file=sys.stderr)
    sys.exit(1)

indent = re.match(r'^(\s+)', lines[block_end_i]).group(1) \
    if re.match(r'^(\s+)', lines[block_end_i]) else '\t\t\t\t\t'

new_lo = indent + '"LaunchOptions"\t\t"' + new_launch_opts + '"\n'
if launch_opts_i != -1:
    lines[launch_opts_i] = new_lo
    insert_after = launch_opts_i
else:
    lines.insert(block_end_i, new_lo)
    block_end_i += 1
    insert_after = block_end_i - 1

if steam_input_i != -1:
    lines[steam_input_i] = indent + '"SteamInput"\t\t"2"\n'
else:
    lines.insert(insert_after + 1, indent + '"SteamInput"\t\t"2"\n')

with open(localconfig_path, 'w', encoding='utf-8') as f:
    f.writelines(lines)

print(f"Updated app {app_id}:")
print(f"  LaunchOptions → {new_launch_opts}")
print(f"  SteamInput    → 2 (disabled)")
PYEOF

printf "%b\n" ""
printf "%b\n" "${GREEN}All fixes applied! Start Steam and launch Binary Domain.${RC}"
