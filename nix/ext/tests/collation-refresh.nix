{ self, pkgs }:
let
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;
  testLib = import ./lib.nix { inherit self pkgs; };
  refresh = self.packages.${system}.postgres-collation-refresh;
  psql = self.packages.${system}."psql_17/bin";
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
        "L+ /var/lib/postgresql/.nix-profile - - - - ${psql}"
        "L+ /nix/var/nix/profiles/site - - - - ${refresh}"
      ];
      systemd.packages = [ refresh ];
      systemd.services.postgresql.wants = [ "postgresql-collation-refresh.service" ];
    };
  testScript = ''
    PSQL = "psql -h localhost -U supabase_admin -d postgres -At -v ON_ERROR_STOP=1"
    UNIT = "postgresql-collation-refresh.service"

    def sql(query):
      return server.succeed(PSQL + " -c \"" + query + "\"").strip()

    def recorded(db):
      return sql("select coalesce(datcollversion, '-') from pg_database where datname = '" + db + "'")

    def set_recorded(db, version):
      sql("update pg_database set datcollversion = '" + version + "' where datname = '" + db + "'")

    start_all()
    server.wait_for_unit("supabase-db-init.service")
    server.wait_for_unit(UNIT)

    DBS = {
      "g": "libc locale = 'en_US.UTF-8'",
      "old": "libc locale = 'en_US.UTF-8'",
      "de": "libc locale = 'de_DE.UTF-8'",
      "c": "libc locale = 'C'",
      "i": "icu locale = 'en_US.UTF-8' icu_locale = 'en-US'",
    }
    for db, options in DBS.items():
      sql("create database " + db + " locale_provider = " + options + " template template0")
    actual = recorded("g")
    fresh = {"g": actual, "old": actual, "de": actual, "i": recorded("i")}

    def reset(stale):
      for db, version in {**fresh, **stale}.items():
        set_recorded(db, version)

    def check(title, stale, refreshed, fails):
      with subtest(title):
        reset(stale)
        status, _ = server.execute("systemctl restart " + UNIT)
        assert (status != 0) == fails, f"unit status {status}, expected failure: {fails}"
        for db, version in stale.items():
          expected = actual if db in refreshed else version
          assert recorded(db) == expected, f"{db}: expected {expected}, got {recorded(db)}"
        assert recorded("c") == "-"

    check("Nothing stale", {}, [], False)
    check("A stale glibc en_US database inside the bounds is refreshed", {"g": "2.31"}, ["g"], False)
    check("ICU and non-English glibc databases are left alone", {"de": "2.31", "i": "1.0"}, [], False)
    check("A database older than 2.31 fails the unit, the others are refreshed", {"old": "2.28", "g": "2.31"}, ["g"], True)

    with subtest("A database that fails to refresh does not stop the others"):
      sql("create role refresher login")
      sql("create database a_other locale_provider = libc locale = 'en_US.UTF-8' template template0")
      sql("create database b_owned owner refresher locale_provider = libc locale = 'en_US.UTF-8' template template0")
      reset({"a_other": "2.31", "b_owned": "2.31"})
      status, _ = server.execute("psql -h localhost -U refresher -d postgres -X -q -f /nix/var/nix/profiles/site/share/postgres-collation-refresh.sql")
      assert status != 0
      assert recorded("a_other") == "2.31"
      assert recorded("b_owned") == actual

    with subtest("A postgres restart reruns the unit and leaves postgres active when it fails"):
      reset({"old": "2.28", "g": "2.31", "a_other": actual})
      server.succeed("systemctl restart postgresql")
      server.wait_until_succeeds("systemctl is-failed " + UNIT)
      server.succeed("systemctl is-active postgresql.service")
      assert recorded("g") == actual
      assert recorded("old") == "2.28"
  '';
}
