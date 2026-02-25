{ self, pkgs }:
let
  pname = "orioledb-rewind";
  testLib = import ./lib.nix { inherit self pkgs; };
in
pkgs.testers.runNixOSTest {
  name = pname;
  nodes.server =
    { ... }:
    {
      imports = [
        (testLib.makeSupabaseTestConfig {
          majorVersion = "15";
        })
      ];

      specialisation.orioledb17.configuration = testLib.makeOrioledbSpecialisation {
        extraConfig = ''
          orioledb.enable_rewind = true
          orioledb.main_buffers = 1280
          orioledb.rewind_max_time = 1200
          orioledb.rewind_max_transactions = 100000
        '';
      };
    };
  testScript =
    { nodes, ... }:
    let
      orioledb17-configuration = "${nodes.server.system.build.toplevel}/specialisation/orioledb17";
    in
    ''
      import time

      orioledb17_configuration = "${orioledb17-configuration}"

      start_all()

      # Wait for full Supabase initialization on PG 15
      server.wait_for_unit("supabase-db-init.service")

      with subtest("Switch to OrioleDB and show rewind config"):
        server.succeed(
          f"{orioledb17_configuration}/bin/switch-to-configuration test >&2"
        )
        server.wait_for_unit("supabase-db-init.service")

        # Verify OrioleDB is running
        installed_extensions = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT extname FROM pg_extension WHERE extname = 'orioledb';\""
        ).strip()
        assert "orioledb" in installed_extensions, (
          f"Expected orioledb extension to be installed, got: {installed_extensions}"
        )

        # Show all rewind-related settings
        rewind_settings = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT name || ' = ' || setting FROM pg_settings WHERE name LIKE 'orioledb.%rewind%' OR name LIKE 'orioledb.%main_buffers%' ORDER BY name;\""
        ).strip()
        print(f"OrioleDB rewind settings:\n{rewind_settings}")

        # Assert rewind is enabled
        rewind_enabled = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SHOW orioledb.enable_rewind;\""
        ).strip()
        assert rewind_enabled == "on", (
          f"Expected orioledb.enable_rewind = on, got: {rewind_enabled}"
        )

        # Print rewind queue/evicted lengths
        queue_len = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT orioledb_get_rewind_queue_length();\""
        ).strip()
        evicted_len = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT orioledb_get_rewind_evicted_length();\""
        ).strip()
        print(f"Initial rewind queue length: {queue_len}")
        print(f"Initial rewind evicted length: {evicted_len}")

      with subtest("Basic rewind"):
        # Phase 1: Setup — matches bash script exactly
        server.succeed(
          "psql -U supabase_admin -d postgres -c \"DROP TABLE IF EXISTS rewind_test; CREATE TABLE rewind_test(x serial) USING orioledb; INSERT INTO rewind_test SELECT FROM generate_series(1, 100);\""
        )

        # Capture xid, oxid, and hash in a single query — matches bash script
        ids = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT pg_current_xact_id()::text::int4, orioledb_get_current_oxid()::int8, md5(string_agg(x::text, '.' ORDER BY x)) FROM rewind_test;\""
        ).strip()
        parts = ids.split("|")
        xid = parts[0]
        oxid = parts[1]
        pre_hash = parts[2]
        print(f"Checkpoint: xid={xid} oxid={oxid} hash={pre_hash}")

        # Phase 2: Dirty the state — matches bash script
        server.succeed(
          "psql -U supabase_admin -d postgres -c \"INSERT INTO rewind_test SELECT FROM generate_series(1, 10); INSERT INTO rewind_test SELECT FROM generate_series(1, 10); INSERT INTO rewind_test SELECT FROM generate_series(1, 10); INSERT INTO rewind_test SELECT FROM generate_series(1, 10);\""
        )
        dirty_count = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT count(*) FROM rewind_test;\""
        ).strip()
        print(f"Rows before rewind: {dirty_count}")
        queue_len = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT orioledb_get_rewind_queue_length();\""
        ).strip()
        evicted_len = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT orioledb_get_rewind_evicted_length();\""
        ).strip()
        print(f"Queue length: {queue_len}, evicted length: {evicted_len}")

        # Phase 3: Rewind — the function crashes postgres, || true absorbs psql error
        print(f"Calling orioledb_rewind_to_transaction({xid}, {oxid})...")
        server.succeed(
          f"psql -U supabase_admin -d postgres -c \"SELECT orioledb_rewind_to_transaction({xid}, {oxid});\" 2>&1 || true"
        )

        # Phase 4: Wait for server restart (systemd Restart=always brings it back)
        print("Waiting for server restart...")
        time.sleep(5)
        server.succeed(
          "until psql -U supabase_admin -d postgres -t -A -c 'SELECT 1' 2>/dev/null; do sleep 1; done"
        )
        print("Server is back up")

        # Verify
        post_hash = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT md5(string_agg(x::text, '.' ORDER BY x)) FROM rewind_test;\""
        ).strip()
        post_count = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT count(*) FROM rewind_test;\""
        ).strip()
        print(f"Rows:       {post_count} (expect 100)")
        print(f"Hash before: {pre_hash}")
        print(f"Hash after:  {post_hash}")
        match = "YES" if pre_hash == post_hash else "NO"
        print(f"Match:       {match}")
        assert post_count == "100", f"Expected 100 rows after rewind, got: {post_count}"
        assert pre_hash == post_hash, f"Hash mismatch: {pre_hash} != {post_hash}"
        print("Basic rewind test PASSED")

      with subtest("Rewind under buffer pressure"):
        # Create a new table for buffer pressure test
        server.succeed(
          "psql -U supabase_admin -d postgres -c \"DROP TABLE IF EXISTS pressure_test; CREATE TABLE pressure_test(x serial) USING orioledb;\""
        )

        # Insert data in 50 batches of 100 rows each (5000 rows across 50 transactions)
        for batch in range(50):
          server.succeed(
            "psql -U supabase_admin -d postgres -c \"INSERT INTO pressure_test SELECT FROM generate_series(1, 100);\""
          )

        # Capture checkpoint state in a single query
        cp_ids = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT pg_current_xact_id()::text::int4, orioledb_get_current_oxid()::int8, count(*) FROM pressure_test;\""
        ).strip()
        cp_parts = cp_ids.split("|")
        cp_xid = cp_parts[0]
        cp_oxid = cp_parts[1]
        cp_count = cp_parts[2]
        print(f"Buffer pressure checkpoint: xid={cp_xid}, oxid={cp_oxid}, count={cp_count}")

        # Insert 10 more batches after checkpoint
        for batch in range(10):
          server.succeed(
            "psql -U supabase_admin -d postgres -c \"INSERT INTO pressure_test SELECT FROM generate_series(1, 100);\""
          )

        after_count = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT count(*) FROM pressure_test;\""
        ).strip()
        print(f"After additional inserts: count={after_count}")

        # Print queue/evicted lengths to show buffer state
        queue_len = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT orioledb_get_rewind_queue_length();\""
        ).strip()
        evicted_len = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT orioledb_get_rewind_evicted_length();\""
        ).strip()
        print(f"Buffer pressure state - queue length: {queue_len}, evicted length: {evicted_len}")

        # Rewind — function crashes postgres
        print(f"Calling orioledb_rewind_to_transaction({cp_xid}, {cp_oxid})...")
        server.succeed(
          f"psql -U supabase_admin -d postgres -c \"SELECT orioledb_rewind_to_transaction({cp_xid}, {cp_oxid});\" 2>&1 || true"
        )

        # Wait for server restart
        time.sleep(5)
        server.succeed(
          "until psql -U supabase_admin -d postgres -t -A -c 'SELECT 1' 2>/dev/null; do sleep 1; done"
        )

        # Verify rewind restored checkpoint state
        post_pressure_count = server.succeed(
          "psql -U supabase_admin -d postgres -t -A -c \"SELECT count(*) FROM pressure_test;\""
        ).strip()
        print(f"After buffer pressure rewind: count={post_pressure_count} (expect {cp_count})")
        assert post_pressure_count == cp_count, (
          f"Expected {cp_count} rows after buffer pressure rewind, got: {post_pressure_count}"
        )
        print("Buffer pressure rewind test PASSED")
    '';
}
