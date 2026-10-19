{ self, pkgs }:
let
  testLib = import ./lib.nix { inherit self pkgs; };

  repairScript = pkgs.writeText "repair-drop-queue.sql" (
    builtins.readFile ../../../ansible/files/postgresql_extension_custom_scripts/pgmq/repair-drop-queue.sql
  );
in
pkgs.testers.runNixOSTest {
  name = "pgmq-drop-queue-repair";
  nodes.server =
    { ... }:
    {
      imports = [
        (testLib.makeSupabaseTestConfig {
          majorVersion = "15";
        })
      ];
    };
  testScript =
    { ... }:
    # python
    ''
      def sql(query):
          return server.succeed(
              "psql -U supabase_admin -d postgres -t -A -F',' -c \"" + query.replace('"', '\\"') + "\""
          ).strip()

      def drop_queue_overloads():
          out = sql(
              "select (d.objid is not null), pg_get_function_identity_arguments(p.oid) "
              "from pg_proc p "
              "left join pg_depend d on d.objid = p.oid and d.deptype = 'e' "
              "  and d.refobjid = (select oid from pg_extension where extname = 'pgmq') "
              "where p.pronamespace = 'pgmq'::regnamespace and p.proname = 'drop_queue' "
              "order by 2;"
          )
          return [line.split(",", 1) for line in out.splitlines() if line]

      def run_repair():
          server.succeed("psql -U supabase_admin -d postgres -f ${repairScript}")

      def assert_fixed():
          overloads = drop_queue_overloads()
          print(f"drop_queue overloads: {overloads}")
          assert overloads == [
              ["t", "queue_name text"],
              ["t", "queue_name text, partitioned boolean"],
          ], f"expected both drop_queue(text) and drop_queue(text, boolean) extension-owned, got: {overloads}"
          sql("select pgmq.create('repair_a'); select pgmq.drop_queue('repair_a');")
          sql("select pgmq.create('repair_b'); select pgmq.drop_queue('repair_b', false);")

      start_all()
      server.wait_for_unit("supabase-db-init.service")

      with subtest("simulate a pre-fix install missing drop_queue(text, boolean)"):
          server.succeed("psql -U supabase_admin -d postgres -c 'DROP EXTENSION IF EXISTS pgmq;'")
          server.succeed(
              "psql -U supabase_admin -d postgres -c \"CREATE EXTENSION pgmq WITH VERSION '1.4.4' CASCADE;\""
          )
          # the old hook detached and dropped the 2-arg member and never
          # re-added it - reproduce exactly that broken shape
          sql("alter extension pgmq drop function pgmq.drop_queue(text, boolean);")
          sql("drop function pgmq.drop_queue(text, boolean);")

          overloads = drop_queue_overloads()
          assert overloads == [["t", "queue_name text"]], (
              f"expected only the 1-arg member before repair, got: {overloads}"
          )

      with subtest("repair restores the 2-arg member"):
          run_repair()
          assert_fixed()

      with subtest("repair is idempotent against an already-fixed install"):
          run_repair()
          assert_fixed()

      with subtest("repair is a no-op when pgmq isn't installed"):
          server.succeed("psql -U supabase_admin -d postgres -c 'DROP EXTENSION pgmq;'")
          run_repair()
          remaining = sql(
              "select count(*) from pg_proc p "
              "join pg_namespace n on n.oid = p.pronamespace "
              "where n.nspname = 'pgmq' and p.proname = 'drop_queue';"
          )
          assert remaining == "0", f"expected no pgmq schema/functions, got {remaining} rows"
    '';
}
