{ self, pkgs }:
let
  testLib = import ./lib.nix { inherit self pkgs; };

  migrationsDir = builtins.path {
    path = ../../../migrations/db/migrations;
    name = "migrations";
  };

  majorVersions = [
    "15"
    "17"
  ];
in
pkgs.testers.runNixOSTest {
  name = "migrations-idempotency";
  nodes = builtins.listToAttrs (
    map (majorVersion: {
      name = "pg${majorVersion}";
      value = {
        imports = [ (testLib.makeSupabaseTestConfig { inherit majorVersion; }) ];
      };
    }) majorVersions
  );
  testScript =
    { ... }:
    # python
    ''
      majors = ${builtins.toJSON majorVersions}
      psql = "psql -v ON_ERROR_STOP=1 -h localhost -U supabase_admin -d postgres"
      # pg_dump emits a random \restrict key on every run
      strip_restrict = "grep -Ev '^\\\\(un)?restrict '"

      def dump(vm, label):
          vm.succeed(
              f"pg_dumpall -h localhost -U supabase_admin --roles-only --no-role-passwords | {strip_restrict} > /tmp/{label}-roles.sql",
              f"pg_dump -h localhost -U supabase_admin -d postgres --schema-only | {strip_restrict} > /tmp/{label}-schema.sql",
          )

      def assert_converged(vm):
          diffs = []
          for kind in ("roles", "schema"):
              rc, out = vm.execute(f"diff -u /tmp/fresh-{kind}.sql /tmp/rerun-{kind}.sql")
              if rc != 0:
                  diffs.append(out)
          assert not diffs, f"{vm.name}: re-running migrations changed roles or schema:\n" + "\n".join(diffs)

      for major in majors:
          vm = globals()[f"pg{major}"]
          with subtest(f"PG {major}: re-running migrations converges"):
              vm.start()
              vm.wait_for_unit("supabase-db-init.service")

              # pgsodium created after the initial migrations, as a user would
              vm.succeed("psql -v ON_ERROR_STOP=1 -h localhost -U postgres -d postgres -c 'create extension pgsodium'")

              dump(vm, "fresh")
              vm.succeed(f"for f in ${migrationsDir}/*.sql; do {psql} -q -f \"$f\" || exit 1; done")
              dump(vm, "rerun")

              assert_converged(vm)
              vm.shutdown()
    '';
}
