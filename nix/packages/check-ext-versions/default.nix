{
  lib,
  writers,
  gh,
  nix,
}:
writers.writeNuBin "check-ext-versions" {
  makeWrapperArgs = [
    "--prefix"
    "PATH"
    ":"
    (lib.makeBinPath [
      gh
      nix
    ])
  ];
} (builtins.readFile ./check-ext-versions.nu)
