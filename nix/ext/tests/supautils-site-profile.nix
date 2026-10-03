# supautils is session-preloaded, so each new backend dlopens it again through
# dynamic_library_path while open sessions keep the copy they loaded. Adding the
# site path to an instance takes a reload; later site profile flips take nothing.
{ self, pkgs }:
let
  testLib = import ./lib.nix { inherit self pkgs; };
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;
  pgBin = "${self.packages.${system}."psql_17/bin"}/bin";
  newSiteEnv = self.packages.${system}.site-env-17;
  # Same supautils source under another name: a distinct store path to swap from.
  oldSupautils = self.legacyPackages.${system}.psql_17.exts.supautils.overrideAttrs (_: {
    name = "supautils-previous";
  });
  oldSiteEnv = pkgs.pkgsLinux.buildEnv {
    name = "site-env-17-previous";
    paths = [ oldSupautils ];
    postBuild = ''
      mkdir -p $out/pg-extensions
      ln -s ../lib/supautils.so $out/pg-extensions/supautils.so
    '';
  };
in
pkgs.testers.runNixOSTest {
  name = "supautils-site-profile";
  nodes.server =
    { ... }:
    {
      imports = [ (testLib.makeSupabaseTestConfig { majorVersion = "17"; }) ];
      virtualisation.additionalPaths = [
        oldSiteEnv
        newSiteEnv
      ];
    };
  testScript = ''
    PG_BIN = "${pgBin}"
    CONNECT = "-h localhost -U supabase_admin"
    CONF = "/var/lib/postgresql/data/postgresql.conf"
    sessions = 0

    def sql(query, db="postgres"):
      return server.succeed(
        f"psql -U supabase_admin -d {db} -X -t -A -v ON_ERROR_STOP=1 -c \"{query}\""
      ).strip()

    def mapped_supautils(pid):
      return server.succeed(
        f"grep -o '/nix/store/[^ ]*/supautils.so' /proc/{pid}/maps | sort -u"
      ).strip()

    def new_session_supautils():
      global sessions
      sessions += 1
      name = f"session-{sessions}"
      server.succeed(
        f"systemd-run --unit={name} -E PGAPPNAME={name} "
        f"{PG_BIN}/psql {CONNECT} -d postgres -X -c 'select pg_sleep(120)'"
      )
      query = f"select pid from pg_stat_activity where application_name = '{name}'"
      server.wait_until_succeeds(f"psql -U supabase_admin -d postgres -X -tA -c \"{query}\" | grep -q .")
      pid = sql(query)
      mapped = mapped_supautils(pid)
      sql(f"select pg_terminate_backend({pid})")
      return mapped

    def start_bench(name, flags):
      log = f"/tmp/{name}.log"
      server.succeed(
        f"systemd-run --unit={name} -p RemainAfterExit=yes "
        f"-p StandardOutput=file:{log} -p StandardError=file:{log} -E PGAPPNAME={name} "
        f"{PG_BIN}/pgbench {CONNECT} -n -S {flags} -R 50 -T 60 bench"
      )

    def finish_bench(name):
      server.wait_until_succeeds(f"systemctl show {name} -p SubState --value | grep -qx exited", timeout=120)
      log = server.succeed(f"cat /tmp/{name}.log")
      status = server.succeed(f"systemctl show {name} -p ExecMainStatus --value").strip()
      assert status == "0", f"{name} exited with {status}:\n{log}"
      assert "number of failed transactions: 0 " in log, f"{name} had failures:\n{log}"

    def set_site_profile(path):
      server.succeed(f"nix-store --realise {path} && nix-env --profile /nix/var/nix/profiles/site --set {path}")

    def resolve(path):
      return server.succeed(f"readlink -f {path}").strip()

    start_all()
    server.wait_for_unit("supabase-db-init.service")
    old_lib = resolve("${oldSiteEnv}/pg-extensions/supautils.so")
    new_lib = resolve("${newSiteEnv}/pg-extensions/supautils.so")
    assert old_lib != new_lib, "old and new site envs ship the same supautils"

    with subtest("Without the site path, sessions load supautils from $libdir"):
      server.succeed(f"cp {CONF} /tmp/postgresql.conf.site")
      server.succeed(f"sed -i '/^dynamic_library_path/d' {CONF}")
      sql("select pg_reload_conf()")
      server.wait_until_succeeds("[ \"$(psql -U supabase_admin -d postgres -X -tA -c 'show dynamic_library_path')\" = '$libdir' ]")
      set_site_profile("${oldSiteEnv}")
      base_lib = new_session_supautils()
      assert base_lib != old_lib, f"$libdir already serves the old site supautils: {base_lib}"
      postmaster = server.succeed("head -1 /var/lib/postgresql/data/postmaster.pid").strip()
      started_at = sql("select pg_postmaster_start_time()")

    with subtest("Start persistent and reconnecting load"):
      server.succeed("createdb -U supabase_admin bench")
      server.succeed(f"{PG_BIN}/pgbench {CONNECT} -i -q bench")
      start_bench("bench-persistent", "-c 2")
      start_bench("bench-reconnect", "-C -c 2")
      query = "select pid from pg_stat_activity where application_name = 'bench-persistent'"
      server.wait_until_succeeds(f"[ $(psql -U supabase_admin -d postgres -X -tA -c \"{query}\" | wc -l) -eq 2 ]")
      persistent = sql(query).splitlines()
      for pid in persistent:
        assert mapped_supautils(pid) == base_lib

    with subtest("Deploying the site path takes effect on reload"):
      server.succeed(f"cp /tmp/postgresql.conf.site {CONF}")
      assert new_session_supautils() == base_lib, "site path applied before the reload"
      sql("select pg_reload_conf()")
      server.wait_until_succeeds(
        "psql -U supabase_admin -d postgres -X -tA -c 'show dynamic_library_path' | grep -q /nix/var/nix/profiles/site/pg-extensions"
      )
      assert new_session_supautils() == old_lib, "a new session did not load supautils from the site profile"
      for pid in persistent:
        assert mapped_supautils(pid) == base_lib, f"persistent backend {pid} lost its supautils"

    with subtest("Flip the site profile without a reload"):
      set_site_profile("${newSiteEnv}")
      assert new_session_supautils() == new_lib, "a new session did not load the new supautils"
      sql("select pg_reload_conf()")
      assert new_session_supautils() == new_lib, "a reload changed what new sessions load"
      for pid in persistent:
        assert mapped_supautils(pid) == base_lib, f"persistent backend {pid} lost its supautils"

    with subtest("Roll back the site profile"):
      server.succeed("nix-env -p /nix/var/nix/profiles/site --rollback")
      assert new_session_supautils() == old_lib

    with subtest("Postmaster never restarted and the load saw no failures"):
      assert server.succeed("head -1 /var/lib/postgresql/data/postmaster.pid").strip() == postmaster
      assert sql("select pg_postmaster_start_time()") == started_at
      finish_bench("bench-persistent")
      finish_bench("bench-reconnect")
  '';
}
