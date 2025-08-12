{
  description = "Prototype tooling for deploying PostgreSQL";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
    nix-editor.url = "github:snowfallorg/nix-editor";
    rust-overlay.url = "github:oxalica/rust-overlay";
    nix-fast-build.url = "github:Mic92/nix-fast-build";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    nixpkgs-go124.url = "github:Nixos/nixpkgs/d2ac4dfa61fba987a84a0a81555da57ae0b9a2b0";
  };

  outputs =
    { flake-utils, ... }@inputs:
    inputs.flake-parts.lib.mkFlake { inherit inputs; } (_: {
      systems = with flake-utils.lib; [
        system.x86_64-linux
        system.aarch64-linux
        system.aarch64-darwin
      ];

      imports = [
        nix/apps.nix
        nix/checks.nix
        nix/config.nix
        nix/devShells.nix
        nix/ext
        nix/fmt.nix
        nix/hooks.nix
        nix/nixpkgs.nix
        nix/packages
        nix/overlays
      ];
    });
}
