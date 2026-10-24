#!/usr/bin/env bash
# ==============================================================================
# osu! Installer (NixOS Edition)
# Forked from: Kitty-Hivens/linux-osu-stable-installer
# NixOS port inspired by: afanetd / GalaxyVinci05 forks
#
# Modified for: NixOS Environment
#  - No GUI (CLI only)
#  - Dependencies provided by Nix (no apt/pacman logic)
#  - CLI arguments supported (--silent, --dir, ...)
#  - Desktop entry / icon / MIME type are provided by the Nix package
# ==============================================================================

set -e

# --- 1. Default Settings ---
INSTALL_DIR="$HOME/.wine-osu"
RENDERER="DXVK"
DRIVER="X11"
FONTS="WenQuanYi (Micro Hei)"
INSTALL_RPC="TRUE"

# --- 2. CLI Argument Parsing ---
show_help() {
    echo "Usage: $0 [OPTIONS]"
    echo "  -s, --silent        Run without GUI (accepted for compatibility)"
    echo "  -d, --dir PATH      Install prefix (Default: ~/.wine-osu)"
    echo "  --renderer TYPE     OpenGL or DXVK (Default: DXVK)"
    echo "  --driver TYPE       X11 or Wayland (Default: X11)"
    echo "  --font NAME         Select font (WenQuanYi, Noto Sans, Koruri, Skip)"
    echo "  --no-rpc            Skip Discord Rich Presence installation"
    echo "  -h, --help          Show this help"
    exit 0
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        -s|--silent) ;;
        -d|--dir) INSTALL_DIR="$2"; shift ;;
        --renderer) RENDERER="$2"; shift ;;
        --driver) DRIVER="$2"; shift ;;
        --font) FONTS="$2"; shift ;;
        --no-rpc) INSTALL_RPC="FALSE" ;;
        -h|--help) show_help ;;
        *) echo "Unknown parameter: $1"; exit 1 ;;
    esac
    shift
done

# --- 3. Dependency Check (Nix Way) ---
REQUIRED_TOOLS="curl unzip winetricks wine"

echo "Checking dependencies..."
for tool in $REQUIRED_TOOLS; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: '$tool' is missing."
        echo "Please ensure your package or shell environment provides these dependencies."
        exit 1
    fi
done

# Find Wine (priority: wine-staging, then wine)
if command -v wine-staging &> /dev/null; then
    WINE_BIN="wine-staging"
elif command -v wine &> /dev/null; then
    WINE_BIN="wine"
else
    echo "ERROR: Wine not found."
    exit 1
fi

WINE_FULL_PATH=$(command -v "$WINE_BIN")
echo "Using Wine: $WINE_FULL_PATH"

# Clean up GUI variables (e.g. "OpenGL (Stable)" -> "OpenGL")
[[ "$RENDERER" == *"DXVK"* ]] && RENDERER="DXVK" || RENDERER="OpenGL"
[[ "$DRIVER" == *"Wayland"* ]] && DRIVER="Wayland" || DRIVER="X11"

echo "=== Config ==="
echo "Prefix:   $INSTALL_DIR"
echo "Wine:     $WINE_BIN"
echo "Renderer: $RENDERER"
echo "Driver:   $DRIVER"
echo "Fonts:    $FONTS"
echo "RPC:      $INSTALL_RPC"
echo "=============="

# --- 4. Task Helper (CLI) ---
run_task() {
    local title="$1"
    local text="$2"
    shift 2
    echo ">> $title: $text"
    "$@"
}

export WINE="$WINE_BIN"
export WINEPREFIX="$INSTALL_DIR"

# --- 5. Prefix and .NET setup ---
mkdir -p "$INSTALL_DIR"

install_dotnet() {
    if [ ! -d "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319" ]; then
        set +e
        WAYLAND_DISPLAY="" winetricks -q dotnet48
        set -e
    else
        echo ".NET already installed."
    fi
}

run_task "Installing .NET" "Setting up .NET 4.8 Framework..." install_dotnet

# --- 6. Graphics Configuration ---
configure_graphics() {
    if [ "$RENDERER" == "DXVK" ]; then
        echo "Installing DXVK..."
        winetricks -q dxvk
    else
        echo "Reverting to OpenGL..."
        "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "d3d9" /f 2>/dev/null || true
        "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "dxgi" /f 2>/dev/null || true
        "$WINE_BIN" reg delete "HKCU\Software\Wine\DllOverrides" /v "d3d11" /f 2>/dev/null || true
    fi

    if [ "$DRIVER" == "Wayland" ]; then
        echo "Enabling Wayland Driver..."
        "$WINE_BIN" reg add "HKCU\Software\Wine\Drivers" /f 2>/dev/null
        "$WINE_BIN" reg add "HKCU\Software\Wine\Drivers" /v "Graphics" /t REG_SZ /d "wayland" /f
    else
        echo "Enforcing X11 Driver..."
        "$WINE_BIN" reg delete "HKCU\Software\Wine\Drivers" /v "Graphics" /f 2>/dev/null || true
    fi
}
run_task "Graphics" "Applying graphics settings ($RENDERER / $DRIVER)..." configure_graphics

# --- 7. Fonts ---
configure_fonts() {
    if [[ "$FONTS" == "Skip" ]]; then return 0; fi

    FONT_DIR="$WINEPREFIX/drive_c/windows/Fonts"
    mkdir -p "$FONT_DIR"
    rm -f "$FONT_DIR/"*

    echo "Installing fonts: $FONTS"
    case "$FONTS" in
      "WenQuanYi"*)
        curl -L -o "$FONT_DIR/wqy-microhei.ttc" "https://github.com/anthonyfok/fonts-wqy-microhei/raw/master/wqy-microhei.ttc"
        REG_NAME="WenQuanYi Micro Hei"
        REG_FILE="wqy-microhei.ttc"
        ;;
      "Noto Sans"*)
        curl -L -o "$FONT_DIR/osu-font.otf" "https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf"
        REG_NAME="Noto Sans CJK JP Regular"
        REG_FILE="osu-font.otf"
        ;;
      "Koruri"*)
        echo "Koruri not fully implemented, skipping download."
        return 0
        ;;
    esac

    if [ -n "$REG_NAME" ]; then
        cat > "$WINEPREFIX/font_fix.reg" << EOF
REGEDIT4
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\FontSubstitutes]
"Arial"="$REG_NAME"
"Segoe UI"="$REG_NAME"
"MS Gothic"="$REG_NAME"
"Meiryo"="$REG_NAME"
[HKEY_LOCAL_MACHINE\Software\Microsoft\Windows NT\CurrentVersion\Fonts]
"$REG_NAME (TrueType)"="$REG_FILE"
[HKEY_CURRENT_USER\Control Panel\Desktop]
"FontSmoothing"="2"
"FontSmoothingGamma"=dword:00000578
"FontSmoothingOrientation"=dword:00000001
"FontSmoothingType"=dword:00000002
[HKEY_LOCAL_MACHINE\System\CurrentControlSet\Control\Nls\CodePage]
"932"="cp932.nls"
"00000411"="cp932.nls"
EOF
        WAYLAND_DISPLAY="" "$WINE_BIN" regedit "$WINEPREFIX/font_fix.reg" 2>/dev/null
        rm "$WINEPREFIX/font_fix.reg"
    fi
}
run_task "Fonts" "Installing fonts..." configure_fonts

# --- 8. Discord RPC ---
install_rpc() {
    if [ "$INSTALL_RPC" != "TRUE" ]; then return 0; fi

    echo "Cleaning old bridge..."
    WAYLAND_DISPLAY="" "$WINE_BIN" net stop rpc-bridge 2>/dev/null || true
    WAYLAND_DISPLAY="" "$WINE_BIN" taskkill /IM bridge.exe /F 2>/dev/null || true
    rm -f "$WINEPREFIX/drive_c/windows/bridge.exe"

    echo "Downloading RPC Bridge..."
    TEMP_DIR="$WINEPREFIX/drive_c/windows/temp_bridge"
    mkdir -p "$TEMP_DIR"
    curl -L -o "$TEMP_DIR/bridge.zip" "https://github.com/EnderIce2/rpc-bridge/releases/latest/download/bridge.zip"
    unzip -o "$TEMP_DIR/bridge.zip" -d "$TEMP_DIR"

    BRIDGE_EXE=$(find "$TEMP_DIR" -name "bridge.exe" | head -n 1)
    if [ -n "$BRIDGE_EXE" ]; then
        WAYLAND_DISPLAY="" "$WINE_BIN" "$BRIDGE_EXE" --install
    fi
    rm -rf "$TEMP_DIR"
}
run_task "Discord RPC" "Installing Rich Presence..." install_rpc

# --- 9. Game Installation ---
TARGET_OSU_EXE=$(find "$WINEPREFIX" -name "osu!.exe" 2>/dev/null | head -n 1)

if [ -z "$TARGET_OSU_EXE" ]; then
    echo "Downloading osu! installer..."
    curl -L -o "$WINEPREFIX/osu!install.exe" "https://m1.ppy.sh/r/osu!install.exe"

    echo "Launching installer..."
    WAYLAND_DISPLAY="" LC_ALL=en_US.UTF-8 "$WINE_BIN" "$WINEPREFIX/osu!install.exe" &

    echo "ACTION REQUIRED:"
    echo "1. Install osu!"
    echo "2. Let it launch."
    echo "3. CLOSE osu! to continue setup."
    wait

    TARGET_OSU_EXE=$(find "$WINEPREFIX" -name "osu!.exe" 2>/dev/null | head -n 1)
fi

if [ -z "$TARGET_OSU_EXE" ]; then
    echo "ERROR: osu!.exe not found after installation."
    exit 1
fi

# Clean up the downloaded installer
rm -f "$WINEPREFIX/osu!install.exe"

# --- 10. Create config and wrapper script ---
CONFIG_DIR="$HOME/.config/osu-importer"
CONFIG_FILE="$CONFIG_DIR/config"
WRAPPER="$CONFIG_DIR/osu_importer_wrapper.sh"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" << EOF
PREFIX="$INSTALL_DIR"
WINE_BIN="$WINE_FULL_PATH"
GAME_EXE="$TARGET_OSU_EXE"
EOF

cat > "$WRAPPER" << 'WRAPPER_EOF'
#!/usr/bin/env bash
exec 2>>/tmp/osu.log
set -x

CONFIG_FILE="$HOME/.config/osu-importer/config"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found at $CONFIG_FILE" >> /tmp/osu.log
    notify-send "osu!stable error" "Configuration not found. Re-run the installer."
    exit 1
fi

source "$CONFIG_FILE"

if [ -z "$PREFIX" ] || [ -z "$WINE_BIN" ] || [ -z "$GAME_EXE" ]; then
    echo "ERROR: Invalid config" >> /tmp/osu.log
    notify-send "osu!stable error" "Corrupted configuration"
    exit 1
fi

export WINEPREFIX="$PREFIX"
export STAGING_AUDIO_DURATION=10000
export PULSE_LATENCY_MSEC=60

if [ ! -f "$GAME_EXE" ]; then
    notify-send "osu!stable error" "osu!.exe not found at: $GAME_EXE"
    exit 1
fi

if command -v gamemoderun &> /dev/null; then
    GM="gamemoderun"
else
    GM=""
fi

if [ -n "$1" ]; then
    FILE_PATH=$("$WINE_BIN" winepath -w "$1")
    $GM "$WINE_BIN" "$GAME_EXE" "$FILE_PATH"
else
    $GM "$WINE_BIN" "$GAME_EXE"
fi
WRAPPER_EOF
chmod +x "$WRAPPER"

echo ""
echo "====================================="
echo "Installation Complete!"
echo "====================================="
echo "Wrapper: $WRAPPER"
echo ""
echo "You can now:"
echo "  - Launch osu!stable from your application menu"
echo "  - Run 'osu' command in terminal"
echo "  - Double-click .osz files to import beatmaps"
echo "====================================="
