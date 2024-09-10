self:
let
  #adapted from the postgresql nixpkgs package
  versions = {
    postgresql_15 = ./15.nix;
    postgresql_16 = ./16.nix;
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
