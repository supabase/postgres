{
  description = "Prototype tooling for deploying PostgreSQL";
  nixConfig = {
    extra-substituters = [ "https://nix-postgres-artifacts.s3.amazonaws.com" ];
    extra-trusted-public-keys = [
      "nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI="
    ];
  };
  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    nix2container.inputs.flake-utils.follows = "flake-utils";
    nix-editor.url = "github:snowfallorg/nix-editor";
    nix-editor.inputs.utils.follows = "flake-utils";
    nix-editor.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    nix-fast-build.url = "github:Mic92/nix-fast-build";
    nix-fast-build.inputs.flake-parts.follows = "flake-parts";
    nix-fast-build.inputs.nixpkgs.follows = "nixpkgs";
    nix-fast-build.inputs.treefmt-nix.follows = "treefmt-nix";
    flake-parts.url = "github:hercules-ci/flake-parts";
    treefmt-nix.url = "github:numtide/treefmt-nix";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks.url = "github:cachix/git-hooks.nix";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    nixpkgs-go124.url = "github:Nixos/nixpkgs/d2ac4dfa61fba987a84a0a81555da57ae0b9a2b0";
    nixpkgs-pgbackrest.url = "github:nixos/nixpkgs/nixos-unstable-small";
    nix-eval-jobs.url = "github:nix-community/nix-eval-jobs";
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
        nix/fmt.nix
        nix/hooks.nix
        nix/nixpkgs.nix
        nix/packages
        nix/overlays
      ];
    });
}
