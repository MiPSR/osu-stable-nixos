{
  description = "osu! stable for NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
  };

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};
      osu = pkgs.callPackage ./package.nix { };
    in {
      packages.${system}.default = osu;

      apps.${system}.default = {
        type = "app";
        program = "${osu}/bin/osu";
      };
    };
}
