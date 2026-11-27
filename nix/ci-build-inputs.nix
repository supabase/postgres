{
  self,
  lib,
  config,
  ...
}:
let
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
        lib.concatMap (lib.collect lib.isDerivation) [
          self.checks.${system}
          self.legacyPackages.${system}
        ]
      )
    )
  );
}
