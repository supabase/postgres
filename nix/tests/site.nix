{ self, pkgs }:
let
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;
  site-env-17 = self.packages.${system}."site-env-17";
  psql_17 = self.legacyPackages.${system}."psql_17".bin;
  psql_17_slim = self.legacyPackages.${system}."psql_17_slim".bin;
  pgConf = pkgs.writeText "postgresql-test.conf" ''
    dynamic_library_path = '/nix/var/nix/profiles/site/lib/postgresql:$libdir'
    session_preload_libraries = 'supautils'
    unix_socket_directories = '/tmp'
  '';
in
pkgs.testers.runNixOSTest {
  name = "site";
  nodes.machine =
    { ... }:
    {
      environment.systemPackages = [ site-env-17 ];
      virtualisation.additionalPaths = [ psql_17 ];
      users.users.postgres = {
        isSystemUser = true;
        group = "postgres";
        shell = pkgs.bash;
      };
      users.groups.postgres = { };
    };
  testScript = ''
    # site profile absent: supautils loads from $libdir
    machine.succeed("install -d -o postgres -g postgres /tmp/pgdata-slim")
    machine.succeed("su postgres -c '${psql_17_slim}/bin/initdb -D /tmp/pgdata-slim'")
    machine.succeed("install -o postgres -g postgres ${pgConf} /tmp/pgdata-slim/postgresql.conf")
    machine.succeed("su postgres -c '${psql_17_slim}/bin/pg_ctl -D /tmp/pgdata-slim -l /tmp/pg-slim.log start'")
    machine.succeed("su postgres -c '${psql_17_slim}/bin/psql -h /tmp -d postgres -c \"select 1\"'")
    machine.succeed("su postgres -c '${psql_17_slim}/bin/pg_ctl -D /tmp/pgdata-slim stop'")

    machine.succeed("nix-env --profile /nix/var/nix/profiles/site --set ${site-env-17}")

    # postgres can load supautils via the site profile's dynamic_library_path
    machine.succeed("install -d -o postgres -g postgres /tmp/pgdata")
    machine.succeed("su postgres -c '${psql_17}/bin/initdb -D /tmp/pgdata'")
    machine.succeed("install -o postgres -g postgres ${pgConf} /tmp/pgdata/postgresql.conf")
    machine.succeed("su postgres -c '${psql_17}/bin/pg_ctl -D /tmp/pgdata -l /tmp/pg.log start'")
    machine.succeed("su postgres -c '${psql_17}/bin/psql -h /tmp -d postgres -c \"select 1\"'")
    machine.succeed("su postgres -c '${psql_17}/bin/pg_ctl -D /tmp/pgdata stop'")

    # site-nix-gc runs to the end and reports what it freed
    machine.succeed("nix-env --profile /nix/var/nix/profiles/default --set $(dirname $(dirname $(readlink -f $(command -v nix-env))))")
    machine.succeed("${site-env-17}/bin/activate")
    machine.succeed("${site-env-17}/bin/site-nix-gc")
    machine.wait_until_fails("systemctl is-active site-nix-gc", timeout=1800)
    print(machine.succeed("journalctl -u site-nix-gc --no-pager | grep freed"))
  '';
}
