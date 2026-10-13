# End-to-end test of the OrioleDB coredump processor in the mode where the
# debug symbols are not installed and realise-postgres-debug has to download
# them. The AMI currently ships them, so testinfra covers the installed mode;
# this keeps the download path working for when it stops doing so.
#
# Uses the processor, units, gdb commands and coredump/sysctl config from
# ansible/files, with a second VM serving the debug env as a binary cache.
{ self', pkgs }:
let
  inherit (pkgs) lib;
  files = ../../ansible/files;
  postgres = self'.packages."postgresql_orioledb-17".withPackages (_: [
    self'.legacyPackages."psql_orioledb-17".exts.orioledb
  ]);
  debugEnv = self'.packages."postgres-env-orioledb-17-debug";
  profile = pkgs.buildEnv {
    name = "postgres-profile";
    paths = [ self'.packages."postgres-env-orioledb-17".realise-postgres-debug ];
  };
  # Installed by ansible to /usr/local/sbin and /etc/systemd/system
  sbin = pkgs.runCommand "orioledb-coredump-sbin" { } ''
    install -Dm755 ${files}/coredump/process-orioledb-coredumps.sh $out/process-orioledb-coredumps.sh
    install -Dm644 ${files}/coredump/cmds.gdb $out/orioledb-coredump-cmds.gdb
  '';
  units = pkgs.runCommand "orioledb-coredump-units" { } ''
    mkdir -p $out/etc/systemd/system
    cp ${files}/coredump/orioledb-coredump.{service,path,timer} $out/etc/systemd/system/
  '';
in
pkgs.testers.runNixOSTest {
  name = "coredump-processor";

  nodes.cache = {
    services.nix-serve.enable = true;
    services.nix-serve.openFirewall = true;
    system.extraDependencies = [ debugEnv ];
  };

  nodes.server =
    { config, ... }:
    {
      virtualisation = {
        memorySize = 2048;
        # Well under the old KeepFree=5G free, like small instances
        diskSize = 3072;
        writableStore = true;
        # /nix/store on the root fs, as on the AMI, not on a RAM-sized tmpfs
        writableStoreUseTmpfs = false;
      };
      nix.settings = {
        substituters = lib.mkForce [ "http://cache:5000" ];
        require-sigs = false;
        connect-timeout = 5;
      };
      environment.systemPackages = [
        postgres
        pkgs.gdb
      ];

      # As on the AMI. The core pattern points at Ubuntu's path for
      # systemd-coredump, and sorts after NixOS's own 60-nixos.conf.
      systemd.coredump.extraConfig = builtins.readFile "${files}/postgresql_config/coredump-storage.conf";
      environment.etc."sysctl.d/99-coredump-core-pattern.conf".source =
        "${files}/postgresql_config/coredump-core-pattern.conf";
      environment.etc."systemd/system.conf.d/disable-coredumps-by-default.conf".source =
        "${files}/postgresql_config/disable-coredumps-by-default.conf";
      boot.kernel.sysctl."fs.suid_dumpable" = 2;
      boot.kernelParams = [ "coredump_filter=0x31" ];

      systemd.tmpfiles.rules = [
        "L+ /usr/lib/systemd/systemd-coredump - - - - ${config.systemd.package}/lib/systemd/systemd-coredump"
        "L+ /bin/bash - - - - ${pkgs.bash}/bin/bash"
        "L+ /var/lib/postgresql/.nix-profile - - - - ${profile}"
        "d /usr/local/sbin 0755 root root -"
        "L+ /usr/local/sbin/process-orioledb-coredumps.sh - - - - ${sbin}/process-orioledb-coredumps.sh"
        "L+ /usr/local/sbin/orioledb-coredump-cmds.gdb - - - - ${sbin}/orioledb-coredump-cmds.gdb"
        "d /var/lib/orioledb-coredumps 0700 root root -"
      ];
      systemd.packages = [ units ];
      # What the unit gets from Ubuntu's default PATH; nix-store from the
      # wrapper's PATH fallback.
      systemd.services.orioledb-coredump = {
        overrideStrategy = "asDropin";
        path = with pkgs; [
          attr
          binutils
          coreutils
          findutils
          gawk
          gdb
          gnugrep
          nix
          systemd
          zstd
        ];
      };

      users.users.postgres = {
        isSystemUser = true;
        group = "postgres";
        home = "/var/lib/postgresql";
        createHome = true;
      };
      users.groups.postgres = { };
      systemd.services.postgresql = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          User = "postgres";
          LimitCORE = "infinity";
          ExecStartPre = pkgs.writeShellScript "postgres-init" ''
            [ -d /var/lib/postgresql/data ] && exit 0
            ${postgres}/bin/initdb -D /var/lib/postgresql/data -U postgres --locale=C
            cat >> /var/lib/postgresql/data/postgresql.conf <<EOF
            shared_preload_libraries = 'orioledb'
            listen_addresses = '''
            unix_socket_directories = '/tmp'
            EOF
          '';
          ExecStart = "${postgres}/bin/postgres -D /var/lib/postgresql/data";
        };
      };
    };

  testScript = ''
    import re

    debug_env = "${debugEnv}"
    coredump_dir = "/var/lib/systemd/coredump"
    bundles_dir = "/var/lib/orioledb-coredumps/diagnostics"
    psql = "psql -h /tmp -U postgres -At"

    start_all()
    cache.wait_for_unit("nix-serve.service")
    cache.wait_for_open_port(5000)
    server.wait_for_unit("postgresql.service")
    server.wait_until_succeeds(f"{psql} -c 'select 1'")
    server.succeed(f"{psql} -c 'create extension orioledb'")
    # Processing is driven by hand below, one step at a time
    server.succeed("systemctl stop orioledb-coredump.path orioledb-coredump.timer")
    server.fail(f"nix-store --check-validity {debug_env}")

    def postgres_cores():
        return server.succeed(f"find {coredump_dir} -name 'core.*postgres*'").split()

    def wait_for_recovery():
        server.wait_until_succeeds(f"{psql} -c 'select 1'", timeout=60)

    def crash_backend():
        n = len(postgres_cores())
        server.execute(f"{psql} -c 'select pg_sleep(600)' >/dev/null 2>&1 &")
        pid = server.wait_until_succeeds(
            f"{psql} -c \"select pid from pg_stat_activity where query like 'select pg_sleep%'\" | grep ."
        ).strip()
        server.succeed(f"kill -SEGV {pid}")
        server.wait_until_succeeds(f"test $(find {coredump_dir} -name 'core.*postgres*' | wc -l) -gt {n}")
        wait_for_recovery()
        return pid

    def crash_bgwriter():
        n = len(postgres_cores())
        pid = server.succeed("pgrep -o -f 'postgres: orioledb background writer'").strip()
        server.succeed(f"kill -SEGV {pid}")
        server.wait_until_succeeds(f"test $(find {coredump_dir} -name 'core.*postgres*' | wc -l) -gt {n}")
        wait_for_recovery()
        return pid

    def process():
        """Run the processor once; True if it exited 0."""
        return server.execute("systemctl start orioledb-coredump.service")[0] == 0

    def bundle(pid):
        return server.succeed(f"cat {bundles_dir}/*-{pid}.txt")

    def assert_symbolized(b):
        assert re.search(r"^debug_symbols: /nix/store/\S+-debug$", b, re.M), b
        assert len(re.findall(r"^    debug file: present$", b, re.M)) == 2, b
        assert re.search(r"^#\d+ .*PostmasterMain \(argc=.* at postmaster\.c:\d+$", b, re.M), b
        assert re.search(r'^\$1 = 0x[0-9a-f]+ ".*postgres', b, re.M), b
        assert not re.search(r"^#\d+ .* from \S*orioledb\.so$", b, re.M), b
        assert "Error in sourced command file" not in b, b
        assert re.search(r"^(rip|pc)\s+0x", b, re.M), b

    with subtest("an unrelated crash neither stores a core nor deletes a waiting one"):
        cache.succeed("systemctl stop nix-serve")
        pid = crash_backend()
        server.succeed("systemd-run --unit=unrelated --collect sleep 600")
        unrelated = server.wait_until_succeeds("systemctl show unrelated -p MainPID --value | grep -v '^0$'").strip()
        server.succeed(f"kill -SEGV {unrelated}")
        server.wait_until_succeeds(f"journalctl -t systemd-coredump | grep -q 'Process {unrelated} .*without generating a coredump'")
        assert len(postgres_cores()) == 1, "the postgres core was deleted"
        server.fail(f"find {coredump_dir} -name 'core.sleep.*' | grep .")

    with subtest("cache unreachable: the core is kept for a retry"):
        assert not process()
        server.succeed("journalctl -u orioledb-coredump.service | grep -q 'debug symbols unavailable, will retry'")
        server.fail(f"ls {bundles_dir}/*-{pid}.txt")
        assert len(postgres_cores()) == 1

    with subtest("journal entries lost: the core is still processed, symbols downloaded"):
        server.succeed("journalctl --rotate && journalctl --vacuum-time=1s")
        server.fail(f"journalctl -t systemd-coredump | grep -q 'Process {pid} '")
        cache.succeed("systemctl start nix-serve")
        cache.wait_for_open_port(5000)
        assert process()
        server.succeed(f"nix-store --check-validity {debug_env}")
        b = bundle(pid)
        assert_symbolized(b)
        assert re.search(r"^#\d+ .*pg_sleep \(.* at misc\.c:\d+$", b, re.M), b
        assert postgres_cores() == []

    with subtest("downloaded symbols are reused, and cover orioledb.so frames"):
        cache.succeed("systemctl stop nix-serve")
        pid = crash_bgwriter()
        assert process()
        b = bundle(pid)
        assert_symbolized(b)
        assert re.search(r"^#\d+ .*bgwriter_main \(.* at src/workers/bgwriter\.c:\d+$", b, re.M), b

    with subtest("not enough disk space: no download, no retries, bundle marked"):
        cache.succeed("systemctl start nix-serve")
        cache.wait_for_open_port(5000)
        server.succeed(f"nix-store --delete $(nix-store -qR {debug_env} | sort | comm -12 - <(nix-store --gc --print-dead 2>/dev/null | sort))")
        server.fail(f"nix-store --check-validity {debug_env}")
        # Leave 1G (KeepFree) + 50M free: less than the reserve after a download
        # The store must take its free space from the same fs as /filler
        server.succeed("test $(df --output=avail / | tail -n 1) = $(df --output=avail /nix/store | tail -n 1)")
        avail = int(server.succeed("df --output=avail -B1 / | tail -n 1").strip())
        server.succeed(f"fallocate -l {avail - (1024 + 50) * 1024 * 1024} /filler")
        pid = crash_backend()
        assert process()
        server.fail(f"nix-store --check-validity {debug_env}")
        b = bundle(pid)
        assert "debug_symbols: UNAVAILABLE, not enough disk space to download them" in b, b
        # Even without symbols: shared libraries and registers come first
        assert re.search(r"^From\s+To\s+Syms Read\s+Shared Object Library", b, re.M), b
        assert re.search(r"^(rip|pc)\s+0x", b, re.M), b
        assert postgres_cores() == []
        server.succeed("rm /filler")

    with subtest("a core removed before processing is recorded, not retried forever"):
        cache.succeed("systemctl stop nix-serve")
        pid = crash_backend()
        assert not process()
        server.succeed(f"rm {coredump_dir}/core.*postgres*")
        assert process()
        server.succeed("journalctl -u orioledb-coredump.service | grep -q 'core was removed before it could be processed'")
        server.succeed(f"ls /var/lib/orioledb-coredumps/state/*-{pid}.done /var/lib/orioledb-coredumps/quarantine/*-{pid}.info")
  '';
}
