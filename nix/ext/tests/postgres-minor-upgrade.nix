# In-place minor upgrade from the previous release on the same data directory:
# flip the postgres profile and the config link, then restart. Config flips with
# the binary because a newer config can set GUCs the older minor rejects.
# The upgraded cluster is then compared against a fresh node.
{ self, pkgs }:
let
  testLib = import ./lib.nix { inherit self pkgs; };
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;
  oldFlake = self.inputs.postgres-previous-release;
  oldVersion = oldFlake.packages.${system}.postgresql_17.version;
  newVersion = testLib.expectedVersions."17";
  profile = "/nix/var/nix/profiles/per-user/postgres/profile";
  oldPkg = oldFlake.packages.${system}.postgres-env-17;
  newPkg = self.packages.${system}.postgres-env-17;
  connProbe = pkgs.pkgsLinux.writeShellApplication {
    name = "conn-probe";
    runtimeInputs = [ pkgs.pkgsLinux.coreutils ];
    text = ''
      export PGCONNECT_TIMEOUT=2
      while true; do
        if /usr/lib/postgresql/bin/psql -h localhost -U supabase_admin -d postgres -X -tAc "select 1" >/dev/null 2>&1; then
          echo "$(date +%s.%N) ok"
        else
          echo "$(date +%s.%N) fail"
        fi
        sleep 0.05
      done
    '';
  };
  configLink = "/var/lib/postgresql/config";
  oldConfig = testLib.processAnsibleConfig {
    majorVersion = "17";
    configDir = "${oldFlake}/ansible/files/postgresql_config";
  };
  newConfig = testLib.processAnsibleConfig { majorVersion = "17"; };
  migrationNames = dir: builtins.attrNames (builtins.readDir dir);
  # Tracked migrations (dbmate) only apply what the old release didn't ship.
  newMigrations = map (name: "${testLib.migrationsDir}/migrations/${name}") (
    pkgs.lib.subtractLists (migrationNames "${oldFlake}/migrations/db/migrations") (
      migrationNames "${testLib.migrationsDir}/migrations"
    )
  );
in
pkgs.testers.runNixOSTest {
  name = "postgres-minor-upgrade";
  nodes.server =
    { ... }:
    {
      imports = [
        (testLib.makeSupabaseTestConfig {
          majorVersion = "17";
          postgresPackage = oldPkg;
          postgresProfile = profile;
          postgresConfig = configLink;
        })
      ];
      # Requires= would restart db-init with postgres and rerun init scripts on the old cluster.
      systemd.services.supabase-db-init = {
        requires = pkgs.lib.mkForce [ ];
        wants = [ "postgresql.service" ];
      };
      systemd.tmpfiles.rules = [ "L ${configLink} - - - - ${oldConfig}" ];
      virtualisation.additionalPaths = [
        newPkg
        newConfig
      ];
    };
  nodes.fresh =
    { ... }:
    {
      imports = [ (testLib.makeSupabaseTestConfig { majorVersion = "17"; }) ];
    };
  testScript = ''
    import difflib

    NEW_BIN = "${newPkg}/bin"
    OLD_VERSION = "${oldVersion}"
    NEW_VERSION = "${newVersion}"
    # pg_cron can only be created in cron.database_name.
    EXTENSION_DATABASE = {"pg_cron": "postgres"}
    EXTENSION_LIBRARIES = (
      "select distinct p.probin from pg_proc p "
      "join pg_depend d on d.classid = 'pg_proc'::regclass and d.objid = p.oid and d.deptype = 'e' "
      "where p.prolang = (select oid from pg_language where lanname = 'c') "
      "order by 1"
    )
    DATABASES = ["postgres", "testing"]
    IDENTITY = (
      "select s.system_identifier, c.timeline_id "
      "from pg_control_system() s, pg_control_checkpoint() c"
    )
    MAX_RECONNECT_GAP = 5.0
    NEW_MIGRATIONS: list[str] = ${builtins.toJSON newMigrations}

    EXTENSION_MEMBERS = (
      "select e.extname, pg_describe_object(d.classid, d.objid, d.objsubid) "
      "from pg_depend d join pg_extension e on e.oid = d.refobjid "
      "where d.refclassid = 'pg_extension'::regclass and d.deptype = 'e' "
      "order by 1, 2"
    )

    def sql(machine, query, db="postgres"):
      return machine.succeed(
        f"psql -U supabase_admin -d {db} -X -t -A -F, -v ON_ERROR_STOP=1 -c \"{query}\""
      ).strip()

    def try_sql(machine, query, db):
      return machine.execute(
        f"psql -U supabase_admin -d {db} -X -t -A -v ON_ERROR_STOP=1 -c \"{query}\" 2>&1"
      )

    def create_extensions(machine, names):
      machine.succeed("createdb -U supabase_admin testing")
      failed = {}
      for name in names:
        db = EXTENSION_DATABASE.get(name, "testing")
        rc, out = try_sql(machine, f"create extension if not exists \\\"{name}\\\" cascade", db)
        if rc != 0:
          failed[name] = out.strip()
      return failed

    def assert_libraries_load(machine, when):
      libraries = sql(machine, EXTENSION_LIBRARIES, "testing").splitlines()
      failures = {}
      for lib in libraries:
        rc, out = try_sql(machine, "load '" + lib.replace("$", "\\$") + "'", "testing")
        if rc != 0:
          failures[lib] = out.strip()
      assert not failures, f"extension libraries fail to load {when}: {failures}"
      return libraries

    def restart(machine):
      machine.succeed("systemctl restart postgresql.service")
      machine.wait_for_unit("postgresql.service")

    def snapshot(machine, db):
      dump = machine.succeed(
        f"{NEW_BIN}/pg_dump -U supabase_admin -d {db} --schema-only --restrict-key=MinorUpgrade"
      )
      return {
        "roles": machine.succeed(
          f"{NEW_BIN}/pg_dumpall -U supabase_admin --roles-only --no-role-passwords --restrict-key=MinorUpgrade"
        ),
        "schema": dump,
        "extension versions": sql(machine, "select extname, extversion from pg_extension order by 1", db),
        "extension members": sql(machine, EXTENSION_MEMBERS, db),
      }

    def diff(name, upgraded, fresh):
      lines = difflib.unified_diff(
        fresh.splitlines(), upgraded.splitlines(), "fresh", "upgraded", lineterm=""
      )
      return [f"{name}:\n" + "\n".join(lines)] if upgraded != fresh else []

    start_all()
    server.wait_for_unit("supabase-db-init.service")
    fresh.wait_for_unit("supabase-db-init.service")

    with subtest("Old cluster starts with every available extension"):
      version = sql(server, "show server_version")
      assert version == OLD_VERSION, f"expected {OLD_VERSION}, got: {version}"
      available = sql(server, "select name from pg_available_extensions order by 1").splitlines()
      failed = create_extensions(server, available)
      report = "\n".join(f"  {name}: {err}" for name, err in sorted(failed.items()))
      assert not failed, f"extensions failed to create:\n{report}"
      created = sql(server, "select extname from pg_extension order by 1", "testing").splitlines()
      libraries_before = assert_libraries_load(server, "before the upgrade")
      server.succeed("createdb -U supabase_admin canary")
      sql(server, "create table upgrade_canary as select generate_series(1, 1000) as i", "canary")
      started_at = sql(server, "select pg_postmaster_start_time()")
      identity = sql(server, IDENTITY)

    with subtest("Fresh baseline with the same extension set"):
      assert not create_extensions(fresh, available), "fresh node could not create the same extension set"

    with subtest("Flip the postgres profile and config and restart"):
      server.succeed("systemd-run --unit=conn-probe --property=StandardOutput=file:/tmp/conn-probe.log ${connProbe}/bin/conn-probe")
      server.sleep(2)
      sql(server, "checkpoint")
      server.succeed("nix-env -p ${profile} --set ${newPkg}")
      server.succeed("ln -sfn ${newConfig} ${configLink}")
      restart(server)
      server.wait_until_succeeds("tail -1 /tmp/conn-probe.log | grep -q ok")
      server.sleep(1)
      server.succeed("systemctl stop conn-probe.service")

    with subtest("New connections come back within the restart window"):
      samples = [line.split() for line in server.succeed("cat /tmp/conn-probe.log").splitlines()]
      ok = [float(ts) for ts, status in samples if status == "ok"]
      failed = sum(1 for _, status in samples if status == "fail")
      gap = max(b - a for a, b in zip(ok, ok[1:]))
      print(f"probe: {len(ok)} ok, {failed} failed, longest gap between successes {gap:.2f}s")
      assert gap < MAX_RECONNECT_GAP, f"new connections failed for {gap:.2f}s"

    with subtest("Same cluster runs the new minor"):
      version = sql(server, "show server_version")
      assert version == NEW_VERSION, f"expected {NEW_VERSION}, got: {version}"
      assert sql(server, "select pg_postmaster_start_time()") != started_at, "postmaster did not restart"
      assert sql(server, "select count(*) from upgrade_canary", "canary") == "1000", "canary rows lost"
      assert sql(server, IDENTITY) == identity, "system identifier or timeline changed"
      postgres = server.succeed("readlink -f /usr/lib/postgresql/bin/postgres").strip()
      assert postgres == server.succeed("readlink -f ${newPkg}/bin/postgres").strip(), (
        f"/usr/lib/postgresql/bin/postgres resolves to {postgres}, not the new env"
      )

    with subtest("Extensions update to the new defaults"):
      for db in DATABASES:
        for ext in sql(server, "select extname from pg_extension order by 1", db).splitlines():
          sql(server, f"alter extension \\\"{ext}\\\" update", db)
        stale = sql(
          server,
          "select e.extname, e.extversion, a.default_version from pg_extension e "
          "join pg_available_extensions a on a.name = e.extname "
          "where e.extversion <> a.default_version",
          db,
        )
        assert not stale, f"extensions behind default in {db}:\n{stale}"

    with subtest("Every extension is still installed and its library loads"):
      after = sql(server, "select extname from pg_extension order by 1", "testing").splitlines()
      assert after == created, f"extension set changed: {sorted(set(created) ^ set(after))}"
      libraries_after = assert_libraries_load(server, "after the upgrade")
      gone = sorted(set(libraries_before) - set(libraries_after))
      assert not gone, f"libraries gone: {gone}"

    with subtest("Migrations the old release didn't ship apply to the upgraded cluster"):
      print(f"{len(NEW_MIGRATIONS)} new migrations")
      for f in NEW_MIGRATIONS:
        server.succeed(f"psql -U supabase_admin -d postgres -X -v ON_ERROR_STOP=1 -f {f}")

    with subtest("Upgraded cluster matches a fresh one"):
      diffs = []
      for db in DATABASES:
        upgraded = snapshot(server, db)
        baseline = snapshot(fresh, db)
        for name in upgraded:
          diffs += diff(f"{db} {name}", upgraded[name], baseline[name])
      assert not diffs, "upgraded cluster differs from a fresh one:\n" + "\n\n".join(diffs)

    with subtest("Roll back to the old minor on data the new one touched"):
      server.succeed("nix-env -p ${profile} --rollback")
      server.succeed("ln -sfn ${oldConfig} ${configLink}")
      restart(server)
      version = sql(server, "show server_version")
      assert version == OLD_VERSION, f"expected {OLD_VERSION} after rollback, got: {version}"
      assert sql(server, IDENTITY) == identity, "system identifier or timeline changed"
      assert sql(server, "select count(*) from upgrade_canary", "canary") == "1000", "canary rows lost"
      assert_libraries_load(server, "after the rollback")
  '';
}
