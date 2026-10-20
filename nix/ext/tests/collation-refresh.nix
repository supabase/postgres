{ self, pkgs }:
let
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;
  testLib = import ./lib.nix { inherit self pkgs; };
  refresh = self.packages.${system}.postgres-collation-refresh;
in
pkgs.testers.runNixOSTest {
  name = "collation-refresh";
  nodes.server =
    { ... }:
    {
      imports = [
        (testLib.makeSupabaseTestConfig {
          majorVersion = "17";
        })
      ];

      i18n.supportedLocales = [
        "C.UTF-8/UTF-8"
        "en_US.UTF-8/UTF-8"
        "de_DE.UTF-8/UTF-8"
      ];

      systemd.tmpfiles.rules = [
        "L+ /var/lib/postgresql/.nix-profile - - - - ${self.packages.${system}."psql_17/bin"}"
        "L+ /nix/var/nix/profiles/site - - - - ${refresh}"
      ];
      systemd.packages = [ refresh ];
      systemd.services.postgresql.wants = [ "postgresql-collation-refresh.service" ];
    };
  testScript = ''
    PSQL = "psql -h localhost -U supabase_admin -d postgres -At -v ON_ERROR_STOP=1"
    REFRESH = "${refresh}/bin/postgres_collation_refresh"

    def sql(query):
      return server.succeed(PSQL + " -c \"" + query + "\"").strip()

    def recorded(db):
      return sql("select coalesce(datcollversion, '-') from pg_database where datname = '" + db + "'")

    def set_recorded(db, version):
      sql("update pg_database set datcollversion = '" + version + "' where datname = '" + db + "'")

    def create(db, options):
      sql("create database " + db + " " + options + " template template0")

    start_all()
    server.wait_for_unit("supabase-db-init.service")
    server.wait_for_unit("postgresql-collation-refresh.service")

    create("g", "locale_provider = libc locale = 'en_US.UTF-8'")
    create("old", "locale_provider = libc locale = 'en_US.UTF-8'")
    create("de", "locale_provider = libc locale = 'de_DE.UTF-8'")
    create("c", "locale_provider = libc locale = 'C'")
    create("i", "locale_provider = icu locale = 'en_US.UTF-8' icu_locale = 'en-US'")
    actual = sql("select pg_database_collation_actual_version(oid) from pg_database where datname = 'g'")
    icu_actual = recorded("i")
    print(f"glibc collation version: {actual}, icu: {icu_actual}")

    def fresh():
      for db in ["g", "old", "de"]:
        set_recorded(db, actual)

    with subtest("Nothing stale is a no-op"):
      server.succeed(REFRESH)

    with subtest("A stale glibc en_US database inside the bounds is refreshed"):
      set_recorded("g", "2.31")
      server.succeed(REFRESH)
      assert recorded("g") == actual, f"expected {actual}, got {recorded('g')}"

    with subtest("ICU, non-English glibc and C databases are left alone and do not fail the run"):
      set_recorded("de", "2.31")
      set_recorded("i", "1.0")
      server.succeed(REFRESH)
      assert recorded("de") == "2.31"
      assert recorded("i") == "1.0"
      assert recorded("c") == "-"
      set_recorded("i", icu_actual)

    with subtest("A database that fails to refresh does not stop the others"):
      fresh()
      sql("create role refresher login")
      sql("create database a_other locale_provider = libc locale = 'en_US.UTF-8' template template0")
      sql("create database b_owned owner refresher locale_provider = libc locale = 'en_US.UTF-8' template template0")
      set_recorded("a_other", "2.31")
      set_recorded("b_owned", "2.31")
      status, _ = server.execute("PGUSER=refresher " + REFRESH)
      assert status == 1, f"expected exit 1, got {status}"
      assert recorded("a_other") == "2.31"
      assert recorded("b_owned") == actual, f"expected {actual}, got {recorded('b_owned')}"
      set_recorded("a_other", actual)

    with subtest("Databases without a recorded version are ignored"):
      sql("update pg_database set datcollversion = null where datname = 'template0'")
      server.succeed(REFRESH)
      assert recorded("template0") == "-"

    with subtest("A postgres restart reruns the unit: it refreshes what it can, fails on a glibc database older than 2.31, and leaves postgres active"):
      fresh()
      set_recorded("old", "2.28")
      set_recorded("g", "2.31")
      server.succeed("systemctl restart postgresql")
      server.wait_until_succeeds(
        PSQL + " -c \"select 1 from pg_database where datname = 'g' and datcollversion = '" + actual + "'\" | grep -q 1"
      )
      server.wait_until_succeeds("systemctl is-failed postgresql-collation-refresh.service")
      server.succeed("systemctl is-active postgresql.service")
      assert recorded("old") == "2.28"
  '';
}
