{ self, pkgs }:
let
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;
  site-env-17 = self.packages.${system}."site-env-17";
  roundtrip = self.packages.${system}.site-profile-roundtrip;
  psql_17 = self.legacyPackages.${system}."psql_17".bin;
  previousSiteEnv = pkgs.pkgsLinux.buildEnv {
    name = "site-env-17-previous";
    paths = [
      (pkgs.pkgsLinux.writeTextDir "share/site-env-previous" "previous")
    ];
  };
  pgRestart = pkgs.pkgsLinux.writeShellScript "pg-restart" ''
    exec su postgres -c '${psql_17}/bin/pg_ctl -D /tmp/pgdata -l /tmp/pg.log restart'
  '';
  psql = pkgs.pkgsLinux.writeShellScript "psql" ''
    exec ${psql_17}/bin/psql -h /tmp -U postgres -X -At "$@"
  '';
  pgConf = pkgs.writeText "postgresql-test.conf" ''
    dynamic_library_path = '/nix/var/nix/profiles/site/lib/postgresql:$libdir'
    session_preload_libraries = 'supautils'
    unix_socket_directories = '/tmp'
  '';
in
pkgs.testers.runNixOSTest {
  name = "site-roundtrip";
  nodes.machine =
    { ... }:
    {
      environment.systemPackages = [
        site-env-17
        roundtrip
      ];
      virtualisation.additionalPaths = [
        psql_17
        previousSiteEnv
      ];
      users.users.postgres = {
        isSystemUser = true;
        group = "postgres";
        shell = pkgs.bash;
      };
      users.groups.postgres = { };
    };
  testScript = ''
    machine.succeed("install -d -o postgres -g postgres /tmp/pgdata")
    machine.succeed("su postgres -c '${psql_17}/bin/initdb -D /tmp/pgdata'")
    machine.succeed("install -o postgres -g postgres ${pgConf} /tmp/pgdata/postgresql.conf")
    machine.succeed("su postgres -c '${psql_17}/bin/pg_ctl -D /tmp/pgdata -l /tmp/pg.log start'")

    machine.succeed("nix-env --profile /nix/var/nix/profiles/site --set ${previousSiteEnv}")

    machine.succeed(
      "PG_RESTART=${pgRestart} PSQL='${psql} -c' "
      "site-profile-roundtrip ${site-env-17} /tmp/manifests"
    )
  '';
}
