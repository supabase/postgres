{ self, ... }:
{
  flake.overlays.default = final: _prev: {
    # NOTE: add any needed overlays here. in theory we could
    # pull them from the overlays/ directory automatically, but we don't
    # want to have an arbitrary order, since it might matter. being
    # explicit is better.

    inherit (self.packages.${final.stdenv.hostPlatform.system})
      postgresql_15
      postgresql_17
      postgresql_orioledb-17
      supabase-groonga
      switch-ext-version
      mecab-naist-jdic
      ;

    xmrig = throw "The xmrig package has been explicitly disabled in this flake.";
  };
}
