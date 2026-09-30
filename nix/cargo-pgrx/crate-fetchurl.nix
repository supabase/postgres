# importCargoLock creates one fetchurl per crate per lock file, and stdenv's
# fetchurl dominates eval time. Nix's builtin fetcher is much cheaper to
# evaluate and yields the same fixed-output store paths.
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
