{
  description = "Tools for deploying PostgreSQL and extensions";

  # Skip rebuilding all the packages, download instead.
  # See nix/docs/binary-cache.nix to set it up.

  inputs = {
    devshell.url = "github:numtide/devshell";
    devshell.inputs.nixpkgs.follows = "nixpkgs";
    flake-parts.url = "github:hercules-ci/flake-parts";
    flake-utils.url = "github:numtide/flake-utils";
    git-hooks.inputs.nixpkgs.follows = "nixpkgs";
    git-hooks.url = "github:cachix/git-hooks.nix";
    multigres.url = "github:multigres/multigres";
    multigres.flake = false;
    nix-darwin.inputs.nixpkgs.follows = "nixpkgs";
    nix-darwin.url = "github:nix-darwin/nix-darwin/nix-darwin-26.05";
    nix-editor.inputs.nixpkgs.follows = "nixpkgs";
    nix-editor.inputs.utils.follows = "flake-utils";
    nix-editor.url = "github:snowfallorg/nix-editor";
    nix-eval-jobs.inputs.flake-parts.follows = "flake-parts";
    nix-eval-jobs.inputs.treefmt-nix.follows = "treefmt-nix";
    nix-eval-jobs.url = "github:nix-community/nix-eval-jobs";
    nix2container.inputs.nixpkgs.follows = "nixpkgs";
    nix2container.url = "github:nlewo/nix2container";
    # Pin to a specific nixpkgs version that has compatible v8 and curl versions
    # for extensions that require older package versions
    nixpkgs-oldstable.url = "github:NixOS/nixpkgs/a76c4553d7e741e17f289224eda135423de0491d";
    # Postgres, its extensions, and anything else loaded into the postgres
    # process stay on glibc 2.40. Postgres warns when the running glibc's
    # collation version differs from the one stored in each database.
    nixpkgs-pg.url = "https://releases.nixos.org/nixos/unstable/nixos-26.05pre921484.fb7944c166a3/nixexprs.tar.xz?rev=fb7944c166a3b630f177938e478f0378e64ce108";
    nixpkgs.url = "https://channels.nixos.org/nixos-26.05/nixexprs.tar.xz";
    rust-overlay.inputs.nixpkgs.follows = "nixpkgs";
    rust-overlay.url = "github:oxalica/rust-overlay";
    treefmt-nix.inputs.nixpkgs.follows = "nixpkgs";
    treefmt-nix.url = "github:numtide/treefmt-nix";
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
        nix/hosts.nix
        nix/nixpkgs.nix
        nix/overlays
        nix/packages
        nix/tools
      ];
    });
}
