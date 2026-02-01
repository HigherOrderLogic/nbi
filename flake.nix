{
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    nixpkgs-unstable.url = "github:nixos/nixpkgs/nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs/nixos-25.11";
  };

  outputs = {
    self,
    nixpkgs,
    nixpkgs-unstable,
    nixpkgs-stable,
    ...
  }: let
    inherit (nixpkgs) lib;

    systems = lib.systems.flakeExposed;
    forEachSystem = fn: lib.genAttrs systems (system: fn system nixpkgs.legacyPackages.${system});
  in {
    formatter = forEachSystem (system: pkgs:
      pkgs.writeShellApplication {
        name = "aljd";
        runtimeInputs = with pkgs; [alejandra fd];
        text = ''
          fd "$@" -t f -e nix -X alejandra -q '{}'
        '';
      });

    apps = forEachSystem (system: pkgs:
      lib.pipe {
        stable = [true false];
        sys = systems;
      } [
        (lib.mapCartesianProduct ({
          stable,
          sys,
        }: let
          nixpkgsSrc =
            if stable
            then nixpkgs-stable
            else nixpkgs-unstable;
          stableText =
            if stable
            then "stable"
            else "unstable";
          folder = "./pkgs/${sys}-${stableText}-index";
        in {
          name = "generate-${sys}-${stableText}-index";
          value = {
            type = "app";
            program = lib.getExe (pkgs.writeShellApplication {
              name = "generate-nix-index";
              runtimeInputs = [pkgs.nix-index];
              text = ''
                mkdir -p ${folder} || rm ${folder}/*
                nix-index --nixpkgs ${nixpkgsSrc} --db ${folder} --system ${sys} --filter-prefix '/bin/'
              '';
            });
          };
        }))
        builtins.listToAttrs
      ]);

    packages = forEachSystem (system: pkgs:
      {
        stable = self.packages.${system}."${system}-stable-index";
        unstable = self.packages.${system}."${system}-unstable-index";
      }
      // lib.pipe ./pkgs [
        builtins.readDir
        (builtins.mapAttrs (k: _:
          pkgs.runCommand "nix-bin-index" {} ''
            cp -r ${./pkgs}/${k} $out
          ''))
      ]);
  };
}
