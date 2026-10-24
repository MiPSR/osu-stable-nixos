{ pkgs }:

let
  runtimeDeps = with pkgs; [
    bash
    wineWow64Packages.staging
    winetricks
    curl
    unzip
    icoutils
    desktop-file-utils
    shared-mime-info
    libnotify
  ];
in
pkgs.stdenv.mkDerivation {
  pname = "osu-stable";
  version = "4.0.0";

  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin

    # Installer script
    cp install-nix.sh $out/bin/osu-install
    chmod +x $out/bin/osu-install

    wrapProgram $out/bin/osu-install \
      --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps} \
      --set STAGING_AUDIO_DURATION 10000 \
      --set PULSE_LATENCY_MSEC 60

    # Launcher: runs the game if installed, otherwise the installer
    cat > $out/bin/osu <<'EOF'
#!/bin/sh
WRAPPER="$HOME/.config/osu-importer/osu_importer_wrapper.sh"
CONFIG="$HOME/.config/osu-importer/config"

if [ -x "$WRAPPER" ] && [ -f "$CONFIG" ]; then
  exec "$WRAPPER" "$@"
else
  echo "osu! is not installed or not configured."
  echo "Launching setup wizard..."
  exec osu-install
fi
EOF
    chmod +x $out/bin/osu
  '';

  meta = with pkgs.lib; {
    description = "Unofficial osu! stable installer and wrapper for NixOS";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "osu";
  };
}
