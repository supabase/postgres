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
} (builtins.readFile ../tools/check-ext-versions.nu)
