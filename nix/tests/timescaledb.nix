{ self, pkgs }:
let
  inherit (pkgs) lib;
  installedExtension = postgresMajorVersion:
    self.packages.${pkgs.system}."psql_${postgresMajorVersion}/exts/timescaledb-all";
  versions = (installedExtension "15").versions;
  firstVersion = lib.head versions;
  latestVersion = lib.last versions;
  postgresqlWithExtension = postgresql:
    let
      majorVersion = lib.versions.major postgresql.version;
      pkg = pkgs.buildEnv {
        name = "postgresql-${majorVersion}-timescaledb";
        paths = [ postgresql postgresql.lib (installedExtension majorVersion) ];
        passthru = {
          inherit (postgresql) version psqlSchema;
          lib = pkg;
          withPackages = _: pkg;
        };
        nativeBuildInputs = [ pkgs.makeWrapper ];
        pathsToLink = [ "/" "/bin" "/lib" ];
        postBuild = ''
          wrapProgram $out/bin/postgres --set NIX_PGLIBDIR $out/lib
          wrapProgram $out/bin/pg_ctl --set NIX_PGLIBDIR $out/lib
          wrapProgram $out/bin/pg_upgrade --set NIX_PGLIBDIR $out/lib
        '';
      };
    in pkg;
in self.inputs.nixpkgs.lib.nixos.runTest {
  name = "timescaledb";
  hostPkgs = pkgs;
  nodes.server = { config, ... }: {
    virtualisation = {
      forwardPorts = [{
        from = "host";
        host.port = 13022;
        guest.port = 22;
      }];
    };
    services.openssh = { enable = true; };
    users.users.root.openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIArkmq6Th79Z4klW6Urgi4phN8yq769/l/10jlE00tU9"
    ];

    services.postgresql = {
      enable = true;
      package =
        postgresqlWithExtension self.packages.${pkgs.system}.postgresql_15;
      settings = { shared_preload_libraries = "timescaledb"; };
    };

    specialisation.postgresql15.configuration = {
      services.postgresql = {
        package = lib.mkForce
          (postgresqlWithExtension self.packages.${pkgs.system}.postgresql_15);
      };
    };
  };
}
