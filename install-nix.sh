#!/usr/bin/env bash
# ==============================================================================
# osu! Installer (NixOS Edition)
# ==============================================================================

set -e

# --- Settings file (single file, no folder) ---
SETTINGS_FILE="$HOME/.config/osu-stable.conf"

# Defaults (resolved below if unset)
RENDERER=""
DRIVER=""
FONTS="WenQuanYi (Micro Hei)"
INSTALL_RPC="TRUE"

# Load existing settings if present
if [ -f "$SETTINGS_FILE" ]; then
    # shellcheck source=/dev/null
    source "$SETTINGS_FILE"
fi

# Resolve defaults when not set by settings
if [ -z "${RENDERER:-}" ]; then
    if command -v vulkaninfo >/dev/null 2>&1 || [ -e /run/opengl-driver/lib/libvulkan.so.1 ] || [ -e /usr/lib/libvulkan.so.1 ]; then
        RENDERER="DXVK"
    else
        RENDERER="OpenGL"
    fi
fi

if [ -z "${DRIVER:-}" ]; then
    if [ -S "/run/user/$(id -u)/wayland-0" ]; then
        DRIVER="Wayland"
    else
        DRIVER="X11"
    fi
fi

# --- Fixed install location ---
INSTALL_DIR="$HOME/osu-stable"

cleanup_all() {
    rm -rf "$INSTALL_DIR"
    rm -rf "$HOME/.config/osu-importer"
    rm -f "$HOME/.config/osu-stable.conf"
    rm -f "$HOME/.local/share/applications/osu-stable.desktop"
    rm -f "$HOME/.local/share/icons/hicolor/256x256/apps/osu-stable.png"
    rm -f "$HOME/.local/share/mime/packages/osu-stable.xml"
    command -v update-mime-database >/dev/null 2>&1 && update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
    command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$HOME/.local/share/applications" 2>/dev/null || true
}

# --- Reinstall ---
if [ "${1:-}" = "--reinstall" ]; then
    echo "Reinstalling osu!stable..."
    cleanup_all
fi

# --- Uninstall ---
if [ "${1:-}" = "--uninstall" ]; then
    echo "Uninstalling osu!stable..."
    cleanup_all
    echo "Done."
    exit 0
fi

# --- Migrate old prefixes if target missing ---
if [ ! -d "$INSTALL_DIR" ]; then
    OLD_PREFIX=""
    if [ -f "$HOME/.config/osu-importer/config" ]; then
        OLD_PREFIX=$(grep '^PREFIX=' "$HOME/.config/osu-importer/config" | head -n1 | cut -d= -f2- | tr -d '"')
    fi
    if [ -z "$OLD_PREFIX" ] || [ ! -d "$OLD_PREFIX" ]; then
        if [ -d "$HOME/.wine-osu" ]; then
            OLD_PREFIX="$HOME/.wine-osu"
        fi
    fi
    if [ -n "$OLD_PREFIX" ] && [ -d "$OLD_PREFIX" ] && [ "$OLD_PREFIX" != "$INSTALL_DIR" ]; then
        echo "Migrating existing install from $OLD_PREFIX to $INSTALL_DIR ..."
        mv "$OLD_PREFIX" "$INSTALL_DIR"
    fi
fi

# --- Dependency check ---
REQUIRED_TOOLS="curl unzip winetricks wine"

echo "Checking dependencies..."
for tool in $REQUIRED_TOOLS; do
    if ! command -v "$tool" &> /dev/null; then
        echo "ERROR: '$tool' is missing."
        exit 1
    fi
done

if command -v wine-staging &> /dev/null; then
    WINE_BIN="wine-staging"
elif command -v wine &> /dev/null; then
    WINE_BIN="wine"
else
    echo "ERROR: Wine not found."
    exit 1
fi

WINE_FULL_PATH=$(command -v "$WINE_BIN")
NOTIFY_DIR="$(dirname "$(command -v notify-send 2>/dev/null)")"
[ -z "$NOTIFY_DIR" ] || [ "$NOTIFY_DIR" = "." ] && NOTIFY_DIR=""

echo "Using Wine: $WINE_FULL_PATH"

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

# Save settings
mkdir -p "$(dirname "$SETTINGS_FILE")"
cat > "$SETTINGS_FILE" << EOF
RENDERER="$RENDERER"
DRIVER="$DRIVER"
FONTS="$FONTS"
INSTALL_RPC="$INSTALL_RPC"
EOF

export WINE="$WINE_BIN"
export WINEPREFIX="$INSTALL_DIR"

mkdir -p "$INSTALL_DIR"

# --- .NET ---
install_dotnet() {
    if [ ! -d "$WINEPREFIX/drive_c/windows/Microsoft.NET/Framework/v4.0.30319" ]; then
        set +e
        WAYLAND_DISPLAY="" winetricks -q dotnet48
        set -e
    else
        echo ".NET already installed."
    fi
}
echo ">> Installing .NET: Setting up .NET 4.8 Framework..."
install_dotnet

# --- Graphics ---
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
echo ">> Graphics: Applying graphics settings ($RENDERER / $DRIVER)..."
configure_graphics

# --- Fonts ---
configure_fonts() {
    if [[ "$FONTS" == "Skip" ]]; then return 0; fi

    FONT_DIR="$WINEPREFIX/drive_c/windows/Fonts"
    mkdir -p "$FONT_DIR"
    rm -f "$FONT_DIR/"*

    echo "Installing fonts: $FONTS"
    case "$FONTS" in
      "WenQuanYi"*)
        [ -f "$FONT_DIR/wqy-microhei.ttc" ] || curl -L -o "$FONT_DIR/wqy-microhei.ttc" "https://github.com/anthonyfok/fonts-wqy-microhei/raw/master/wqy-microhei.ttc"
        REG_NAME="WenQuanYi Micro Hei"
        REG_FILE="wqy-microhei.ttc"
        ;;
      "Noto Sans"*)
        [ -f "$FONT_DIR/osu-font.otf" ] || curl -L -o "$FONT_DIR/osu-font.otf" "https://github.com/googlefonts/noto-cjk/raw/main/Sans/OTF/Japanese/NotoSansCJKjp-Regular.otf"
        REG_NAME="Noto Sans CJK JP Regular"
        REG_FILE="osu-font.otf"
        ;;
      "Koruri"*)
        echo "Koruri not fully implemented, skipping download."
        return 0
        ;;
    esac

    if [ -n "${REG_NAME:-}" ]; then
        cat > "$WINEPREFIX/font_fix.reg" << EOFREG
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
EOFREG
        WAYLAND_DISPLAY="" "$WINE_BIN" regedit "$WINEPREFIX/font_fix.reg" 2>/dev/null
        rm "$WINEPREFIX/font_fix.reg"
    fi
}
echo ">> Fonts: Installing fonts..."
configure_fonts

# --- Discord RPC ---
install_rpc() {
    if [ "$INSTALL_RPC" != "TRUE" ]; then return 0; fi

    if [ -f "$WINEPREFIX/drive_c/windows/bridge.exe" ]; then
        echo "RPC bridge already installed, skipping."
        return 0
    fi

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
echo ">> Discord RPC: Installing Rich Presence..."
install_rpc

# --- Game installation ---
TARGET_OSU_EXE=$(find "$WINEPREFIX" -name "osu!.exe" 2>/dev/null | head -n 1)

if [ -n "$TARGET_OSU_EXE" ]; then
    echo "osu! already present, updating settings instead..."
fi

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

rm -f "$WINEPREFIX/osu!install.exe"

# --- Icon ---
if [ -n "${OSU_ICON:-}" ] && [ -f "$OSU_ICON" ]; then
    ICON_DIR="$HOME/.local/share/icons/hicolor/256x256/apps"
    mkdir -p "$ICON_DIR"
    cp "$OSU_ICON" "$ICON_DIR/osu-stable.png"
fi

# --- Config + wrapper ---
CONFIG_DIR="$HOME/.config/osu-importer"
CONFIG_FILE="$CONFIG_DIR/config"
WRAPPER="$CONFIG_DIR/osu_importer_wrapper.sh"
mkdir -p "$CONFIG_DIR"

cat > "$CONFIG_FILE" << EOF
PREFIX="$INSTALL_DIR"
WINE_BIN="$WINE_FULL_PATH"
GAME_EXE="$TARGET_OSU_EXE"
EOF

{
    echo '#!/usr/bin/env bash'
    echo 'exec 2>>/tmp/osu.log'
    if [ -n "$NOTIFY_DIR" ]; then
        printf 'export PATH="%s:$PATH"\n' "$NOTIFY_DIR"
    fi
    echo 'set -x'
    cat << 'WRAPPER_EOF'

CONFIG_FILE="$HOME/.config/osu-importer/config"

if [ ! -f "$CONFIG_FILE" ]; then
    echo "ERROR: Config file not found at $CONFIG_FILE" >> /tmp/osu.log
    if command -v notify-send >/dev/null 2>&1; then notify-send "osu!stable error" "Configuration not found. Re-run the installer."; fi
    exit 1
fi

source "$CONFIG_FILE"

if [ -z "$PREFIX" ] || [ -z "$WINE_BIN" ] || [ -z "$GAME_EXE" ]; then
    echo "ERROR: Invalid config" >> /tmp/osu.log
    if command -v notify-send >/dev/null 2>&1; then notify-send "osu!stable error" "Corrupted configuration"; fi
    exit 1
fi

export WINEPREFIX="$PREFIX"
export STAGING_AUDIO_DURATION=10000
export PULSE_LATENCY_MSEC=60

if [ ! -f "$GAME_EXE" ]; then
    if command -v notify-send >/dev/null 2>&1; then notify-send "osu!stable error" "osu!.exe not found at: $GAME_EXE"; fi
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
} > "$WRAPPER"
chmod +x "$WRAPPER"

# --- User desktop entry + mime ---
DESKTOP_DIR="$HOME/.local/share/applications"
MIME_DIR="$HOME/.local/share/mime/packages"
mkdir -p "$DESKTOP_DIR" "$MIME_DIR"

cat > "$DESKTOP_DIR/osu-stable.desktop" << EOF
[Desktop Entry]
Name=osu!stable
Comment=Rhythm is just a click away
Exec=osu %f
Icon=osu-stable
Terminal=false
Type=Application
Categories=Game;
StartupWMClass=osu!.exe
MimeType=application/x-osu-beatmap-archive;
EOF

cat > "$MIME_DIR/osu-stable.xml" << 'MIME_EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-osu-beatmap-archive">
    <comment>osu! Beatmap Archive</comment>
    <glob pattern="*.osz"/>
  </mime-type>
</mime-info>
MIME_EOF

command -v update-mime-database >/dev/null 2>&1 && update-mime-database "$HOME/.local/share/mime" 2>/dev/null || true
command -v update-desktop-database >/dev/null 2>&1 && update-desktop-database "$DESKTOP_DIR" 2>/dev/null || true

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
