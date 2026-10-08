{ self, pkgs }:
let
  pname = "pgmq";
  inherit (pkgs) lib;
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;
  testLib = import ./lib.nix { inherit self pkgs; };

  installedExtension = self.legacyPackages.${system}."psql_15".exts."${pname}";
  versions = installedExtension.versions;
in
pkgs.testers.runNixOSTest {
  name = "pgmq-drop-queue-overload";
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
    let
      versionList = lib.concatStringsSep ", " (map (v: ''"${v}"'') versions);
    in
    ''
      versions = [${versionList}]

      def sql(query):
          return server.succeed(
              "psql -U supabase_admin -d postgres -t -A -F',' -c \"" + query.replace('"', '\\"') + "\""
          ).strip()

      def drop_queue_overloads():
          # owned flag first: pg_get_function_identity_arguments() can itself
          # contain a comma ("queue_name text, partitioned boolean"), so put the
          # single-char flag first and split on the first comma only.
          out = sql(
              "select (d.objid is not null), pg_get_function_identity_arguments(p.oid) "
              "from pg_proc p "
              "left join pg_depend d on d.objid = p.oid and d.deptype = 'e' "
              "  and d.refobjid = (select oid from pg_extension where extname = 'pgmq') "
              "where p.pronamespace = 'pgmq'::regnamespace and p.proname = 'drop_queue' "
              "order by 2;"
          )
          return [line.split(",", 1) for line in out.splitlines() if line]

      # every calling convention drop_queue has ever supported still works
      def check_callers(qname):
          sql(f"select pgmq.create('{qname}_a'); select pgmq.drop_queue('{qname}_a');")
          sql(f"select pgmq.create('{qname}_b'); select pgmq.drop_queue('{qname}_b', false);")
          # WRONG flag on purpose (queue isn't partitioned) - must still
          # succeed, safely ignored in favour of pgmq.meta
          sql(f"select pgmq.create('{qname}_c'); select pgmq.drop_queue('{qname}_c', true);")
          sql(
              f"select pgmq.create('{qname}_d'); "
              f"select pgmq.drop_queue(queue_name => '{qname}_d', partitioned => true);"
          )

      start_all()
      server.wait_for_unit("supabase-db-init.service")

      # fresh install of each pinned version: check the overload split, then the callers
      for version in versions:
          with subtest(f"install pgmq {version}"):
              server.succeed("psql -U supabase_admin -d postgres -c 'DROP EXTENSION IF EXISTS pgmq;'")
              server.succeed(
                  f"psql -U supabase_admin -d postgres -c \"CREATE EXTENSION pgmq WITH VERSION '{version}' CASCADE;\""
              )

              overloads = drop_queue_overloads()
              print(f"[{version}] drop_queue overloads: {overloads}")
              assert overloads == [
                  ["t", "queue_name text"],
                  ["t", "queue_name text, partitioned boolean"],
              ], (
                  f"[{version}] expected both drop_queue(text) and "
                  f"drop_queue(text, boolean) extension-owned, got: {overloads}"
              )

              check_callers(f"q_{version.replace('.', '_')}")

      # DROP EXTENSION must remove both signatures, leaving nothing behind
      # for a later CREATE EXTENSION to collide with
      with subtest("DROP EXTENSION leaves no drop_queue behind"):
          server.succeed("psql -U supabase_admin -d postgres -c 'DROP EXTENSION pgmq;'")
          remaining = sql(
              "select count(*) from pg_proc p "
              "join pg_namespace n on n.oid = p.pronamespace "
              "where n.nspname = 'pgmq' and p.proname = 'drop_queue';"
          )
          assert remaining == "0", f"expected no leftover drop_queue, got {remaining} rows"
    '';
}
