self:
let
  versions = {
    postgresql_15 = ./15.nix;
    postgresql_17 = ./17.nix;
    postgresql_orioledb-17 = ./orioledb-17.nix;
  };
  mkAttributes = jitSupport:
    self.lib.mapAttrs' (version: path:
      let
        attrName = if jitSupport then "${version}_jit" else version;
      in
      self.lib.nameValuePair attrName (import path {
        inherit jitSupport self;
      })
    ) versions;
in
# variations without and with JIT
(mkAttributes false) // (mkAttributes true)
