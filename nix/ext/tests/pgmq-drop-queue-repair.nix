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
              "psql -U supabase_admin -d postgres -t -A -c \"" + query.replace('"', '\\"') + "\""
          ).strip()

      def run_repair():
          server.succeed("psql -U supabase_admin -d postgres -f ${repairScript}")

      start_all()
      server.wait_for_unit("supabase-db-init.service")

      with subtest("repairs a pre-fix install missing the 2-arg shim"):
          server.succeed("psql -U supabase_admin -d postgres -c 'DROP EXTENSION IF EXISTS pgmq;'")
          server.succeed(
              "psql -U supabase_admin -d postgres -c \"CREATE EXTENSION pgmq WITH VERSION '1.4.4' CASCADE;\""
          )
          sql("alter extension pgmq drop function pgmq.drop_queue(text, boolean);")
          sql("drop function pgmq.drop_queue(text, boolean);")

          run_repair()
          sql("select pgmq.create('q'); select pgmq.drop_queue('q', false);")

      with subtest("no-op when already fixed or pgmq isn't installed"):
          run_repair()
          server.succeed("psql -U supabase_admin -d postgres -c 'DROP EXTENSION pgmq;'")
          run_repair()
    '';
}
