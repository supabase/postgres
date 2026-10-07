{ writeShellApplication, stdenv }:
let
  linuxSystem = if stdenv.hostPlatform.isAarch64 then "aarch64-linux" else "x86_64-linux";
in
writeShellApplication {
  name = "collation-compare";
  text = ''
    if [ $# -lt 2 ]; then
      echo "Usage: collation-compare <old-nixpkgs> <new-nixpkgs> [locale ...]" >&2
      echo "Compares glibc sort order for en_US.UTF-8 and C.UTF-8, or for the" >&2
      echo "given glibcLocales entries such as de_DE.UTF-8/UTF-8." >&2
      echo "Example: collation-compare github:NixOS/nixpkgs/<rev> github:NixOS/nixpkgs/nixos-26.05" >&2
      exit 2
    fi
    old=$1 new=$2
    shift 2
    locales=collation.shippedLocales
    if [ $# -gt 0 ]; then
      locales="[$(printf '"%s" ' "$@")]"
    fi
    nix build --no-link --print-out-paths -L --impure --expr "
      let
        system = \"${linuxSystem}\";
        load = ref: import (builtins.getFlake ref).outPath { inherit system; };
        collation = import ${../tests/collation} { pkgs = load \"$new\"; };
      in
      collation.compare {
        old = load \"$old\";
        new = load \"$new\";
        locales = $locales;
      }
    " | xargs cat
  '';
}
