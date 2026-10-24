{ pkgs }:

let
  runtimeDeps = with pkgs; [
    bash
    wineWow64Packages.staging
    winetricks
    curl
    unzip
    libnotify
  ];

  # Official osu! "full colour cookie" logo, fetched at build time from the
  # brand identity guidelines (see README). Not committed to the repo.
  osuIcon = pkgs.fetchurl {
    url = "https://osu.ppy.sh/wiki/images/Brand_identity_guidelines/img/usage-full-colour.png";
    sha256 = "facc5f53b038c4c15a8958a2d55bbef937235a96207f47eeaa8d44d993a74b7c";
  };
in
pkgs.stdenv.mkDerivation {
  pname = "osu-stable";
  version = "4.0.0";

  src = ./.;

  nativeBuildInputs = [ pkgs.makeWrapper ];

  installPhase = ''
    mkdir -p $out/bin
    mkdir -p $out/share/applications
    mkdir -p $out/share/icons/hicolor/256x256/apps
    mkdir -p $out/share/mime/packages
    mkdir -p $out/share/pixmaps

    cp ${osuIcon} $out/share/icons/hicolor/256x256/apps/osu-stable.png
    cp ${osuIcon} $out/share/pixmaps/osu-stable.png

    cp install-nix.sh $out/bin/osu-install
    chmod +x $out/bin/osu-install

    wrapProgram $out/bin/osu-install \
      --prefix PATH : ${pkgs.lib.makeBinPath runtimeDeps} \
      --set STAGING_AUDIO_DURATION 10000 \
      --set PULSE_LATENCY_MSEC 60

    cat > $out/bin/osu <<'EOF'
#!/bin/sh
WRAPPER="$HOME/.config/osu-importer/osu_importer_wrapper.sh"
CONFIG="$HOME/.config/osu-importer/config"

if [ -x "$WRAPPER" ] && [ -f "$CONFIG" ]; then
  exec "$WRAPPER" "$@"
else
  echo "osu!stable is not installed or not configured."
  echo "Launching setup wizard..."
  exec osu-install
fi
EOF
    chmod +x $out/bin/osu

    cat > $out/share/applications/osu-stable.desktop <<'EOF'
[Desktop Entry]
Name=osu!stable
Comment=Rhythm is just a click away
Exec=osu
Icon=osu-stable
Terminal=false
Type=Application
Categories=Game;
StartupWMClass=osu!.exe
MimeType=application/x-osu-beatmap-archive;
EOF

    cat > $out/share/mime/packages/osu-stable.xml <<'EOF'
<?xml version="1.0" encoding="UTF-8"?>
<mime-info xmlns="http://www.freedesktop.org/standards/shared-mime-info">
  <mime-type type="application/x-osu-beatmap-archive">
    <comment>osu! Beatmap Archive</comment>
    <glob pattern="*.osz"/>
  </mime-type>
</mime-info>
EOF
  '';

  meta = with pkgs.lib; {
    description = "Unofficial osu! stable installer and wrapper for NixOS";
    license = licenses.mit;
    platforms = [ "x86_64-linux" ];
    mainProgram = "osu";
  };
}
