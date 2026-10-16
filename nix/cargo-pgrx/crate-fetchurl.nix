rustPlatform:
rustPlatform.overrideScope (
  _final: prev: {
    importCargoLock = prev.importCargoLock.override {
      fetchurl =
        args:
        import <nix/fetchurl.nix> {
          inherit (args) name url sha256;
        };
    };
  }
)
