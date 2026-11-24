{
  self,
  lib,
  config,
  ...
}:
let
  derivationsIn =
    value:
    if lib.isDerivation value then
      [ value ]
    else if lib.isAttrs value then
      lib.concatMap derivationsIn (lib.attrValues value)
    else
      [ ];

  # NixOS tests are lazy derivations, which hide drvAttrs.
  buildAttrs = drv: drv.drvAttrs or drv.config.rawTestDerivation.drvAttrs or { };

  directInputs =
    drv:
    lib.concatLists (
      lib.mapAttrsToList (
        path: context:
        map (output: builtins.unsafeDiscardStringContext (import path).${output}.outPath) (
          context.outputs or [ ]
        )
      ) (builtins.getContext (builtins.toJSON (buildAttrs drv)))
    );
in
{
  flake.ciBuildInputs = lib.genAttrs config.systems (
    system:
    lib.unique (
      lib.concatMap directInputs (
        derivationsIn self.checks.${system} ++ derivationsIn self.legacyPackages.${system}
      )
    )
  );
}
