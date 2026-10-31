# Update Nix Dependencies

This document explains how to update various dependencies used in the nix configuration.

## Updating Packer

Packer is used for creating machine images and is defined in `nix/packages/packer.nix`.

### Steps to update Packer version:

1. Bump `version` in `nix/packages/packer.nix`.
2. Set `hash = lib.fakeHash;`, or an empty string.
3. Run `nix build .#packer`, then copy the hash from the error into `hash`.
4. Do the same for `vendorHash`.
5. Run `nix flake check -L`.

### Notes:
- Always check the [Packer changelog](https://github.com/hashicorp/packer/releases) for breaking changes
- Packer uses Go, so ensure compatibility with the Go version specified in the flake inputs
- The current Go version is specified in `flake.nix` under `nixpkgs-go124` input
- If updating to a major version, test all packer templates (`.pkr.hcl` files) in the repository

## Updating Other Dependencies

Similar patterns can be followed for other dependencies defined in the nix packages. Always:

1. Check for breaking changes in changelogs
2. Update version numbers and hashes
3. Run local tests
4. Verify functionality before creating PR

## Updating nixpkgs

`nixpkgs` tracks the current NixOS stable channel and builds everything, including Postgres and its extensions. Update it with `nix flake update nixpkgs`. When the stable release changes, also move `nix-darwin` to the matching `nix-darwin-YY.MM` branch.

A nixpkgs update can change glibc. After a glibc change, Postgres warns that the collation version stored in each database differs from the running one, until each database runs `ALTER DATABASE ... REFRESH COLLATION VERSION`.
