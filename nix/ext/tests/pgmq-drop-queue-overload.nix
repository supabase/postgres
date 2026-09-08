{ self, pkgs }:
let
  pname = "pgmq";
  inherit (pkgs) lib;
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;
  testLib = import ./lib.nix { inherit self pkgs; };

  installedExtension = self.legacyPackages.${system}."psql_15".exts."${pname}";
  # boundary versions only - the fix doesn't branch on extversion, so
  # oldest/newest is enough to catch a regression
  versions = lib.unique [
    (lib.head installedExtension.versions)
    (lib.last installedExtension.versions)
  ];
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
    # python
    ''
      versions = [${versionList}]

      def sql(query):
          return server.succeed(
              "psql -U supabase_admin -d postgres -t -A -c \"" + query.replace('"', '\\"') + "\""
          ).strip()

      def assert_single_merged_overload(version):
          ok = sql(
              "select count(*) = 1 "
              "  and bool_and(d.objid is not null) "
              "  and bool_and(pg_get_function_identity_arguments(p.oid) = 'queue_name text, partitioned boolean') "
              "from pg_proc p "
              "join pg_depend d on d.objid = p.oid and d.deptype = 'e' "
              "  and d.refobjid = (select oid from pg_extension where extname = 'pgmq') "
              "where p.pronamespace = 'pgmq'::regnamespace and p.proname = 'drop_queue';"
          )
          assert ok == "t", f"[{version}] expected exactly one merged, extension-owned drop_queue(text, boolean)"

      start_all()
      server.wait_for_unit("supabase-db-init.service")

      for version in versions:
          with subtest(f"install pgmq {version}"):
              server.succeed("psql -U supabase_admin -d postgres -c 'DROP EXTENSION IF EXISTS pgmq;'")
              server.succeed(
                  f"psql -U supabase_admin -d postgres -c \"CREATE EXTENSION pgmq WITH VERSION '{version}' CASCADE;\""
              )

              assert_single_merged_overload(version)

              qname = f"q_{version.replace('.', '_')}"
              sql(f"select pgmq.create('{qname}_a'); select pgmq.drop_queue('{qname}_a');")
              sql(f"select pgmq.create('{qname}_b'); select pgmq.drop_queue('{qname}_b', false);")
    '';
}
