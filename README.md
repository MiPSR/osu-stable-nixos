# osu! stable for NixOS

A simple, self-contained Nix flake that installs and runs **osu!stable** on NixOS using Wine.

Forked/cleaned from the NixOS ports by [afanetd](https://github.com/afanetd/linux-osu-stable-installer-nixos) and [GalaxyVinci05](https://github.com/GalaxyVinci05/linux-osu-stable-installer-nixos), originally based on [Kitty-Hivens/linux-osu-stable-installer](https://github.com/Kitty-Hivens/linux-osu-stable-installer).

## Features

* **Nix-native:** Wine Staging, Winetricks, Curl, etc. provided by Nix.
* **Self-contained:** first run downloads osu! and sets up the wine prefix automatically.
* **Working importer:** double-click `.osz`/`.osk` files to import beatmaps.
* **Low latency:** `STAGING_AUDIO_DURATION` and `PULSE_LATENCY_MSEC` set automatically.

## Usage

### Run without installing

```bash
nix run github:MiPSR/osu-stable-nixos
```

### Install into your profile

```bash
nix profile install github:MiPSR/osu-stable-nixos
```

### Add to a NixOS system configuration

```nix
{
  inputs.osu-stable-nixos.url = "github:MiPSR/osu-stable-nixos";

  # in your nixosConfiguration:
  environment.systemPackages = [ inputs.osu-stable-nixos.packages.x86_64-linux.default ];
}
```

Then rebuild:

```bash
sudo nixos-rebuild switch --flake .#my-machine
```

## How to use

1. Run `osu` (or launch from your application menu).
2. **First run:** the installer runs and downloads osu!. Follow the prompts.
3. **Later runs:** the game launches immediately.

### Importing maps/skins

Double-click any `.osz` or `.osk` file in your file manager; the wrapper passes it to the game.

## Installer CLI flags

```bash
osu-install [options]
```

| Flag | Argument | Description |
| --- | --- | --- |
| `-s`, `--silent` | — | Accepted for compatibility (installer is CLI-only) |
| `-d`, `--dir` | `<path>` | Custom install directory for osu! |
| `--renderer` | `<name>` | Force renderer (`DXVK` or `OpenGL`) |
| `--driver` | `<name>` | Force window driver (`X11` or `Wayland`) |
| `--font` | `<name>` | Font to install (`WenQuanYi`, `Noto Sans`, `Koruri`, `Skip`) |
| `--no-rpc` | — | Disable Discord Rich Presence installation |
| `-h`, `--help` | — | Show help |

## Troubleshooting

If the game doesn't start, check the wrapper log:

```bash
cat /tmp/osu.log
```

## Notes

* The app appears as **osu!stable**.
* Icon is the official full-colour cookie from the [osu! brand identity guidelines](https://osu.ppy.sh/wiki/en/Brand_identity_guidelines), fetched at build time.
* MIME type is registered, but your existing default handler for `.osz` is not overridden.

## License

This project is released into the public domain (Unlicense). See [LICENSE](LICENSE).