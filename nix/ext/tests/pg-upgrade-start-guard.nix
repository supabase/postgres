{ self, pkgs }:
let
  inherit (pkgs) lib;
  pg15 = self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}."psql_15/bin";
  pg17 = self.packages.${pkgs.pkgsLinux.stdenv.hostPlatform.system}."psql_17/bin";

  dataOld = "/var/lib/postgresql/data";
  dataNew = "/var/lib/postgresql/data-17";

  initiate = builtins.path {
    path = ../../../ansible/files/admin_api_scripts/pg_upgrade_scripts/initiate.sh;
    name = "initiate.sh";
  };

  # initiate.sh runs the upgrade when sourced, so extract only the guard.
  guard = pkgs.pkgsLinux.runCommand "start-guard.sh" { } ''
    awk '
      /^PG_UPGRADE_(LOCK|PID|INITIATE|START)_[A-Z_]+=/ { print }
      /^(block_postgres_start|start_pid_lock_watcher|unblock_postgres_start|assert_source_stayed_down)\(\) \{/ { printing = 1 }
      printing { print }
      printing && /^}/ { printing = 0 }
    ' ${initiate} >$out
  '';

  drive = pkgs.pkgsLinux.writeShellApplication {
    name = "drive";
    runtimeInputs = with pkgs.pkgsLinux; [
      bash
      coreutils
      diffutils
      procps
      systemd
      util-linux
    ];
    checkPhase = "";
    text = ''
      IS_CI=""
      PGDATAOLD=${dataOld}
      PGDATANEW=${dataNew}
      log() { echo "[$(date +%T)] $*"; }
      retry() {
        local n=$1 i
        shift
        for i in $(seq 1 "$n"); do
          "$@" && return 0
          sleep 1
        done
        return 1
      }
      . ${guard}

      hold_block() {
        systemctl stop postgresql
        block_postgres_start
        exec sleep infinity
      }

      hold_lock() {
        PGDATANEW=/tmp/fake-new
        mkdir -p "$PGDATANEW"
        runuser -u postgres -- bash -c 'sleep infinity; true' fake-pg-upgrade "--old-datadir=$PGDATAOLD" &
        start_pid_lock_watcher
        touch "$PGDATANEW/postmaster.pid"
        wait
      }

      salt_sim() {
        : >/tmp/salt-states
        while :; do
          systemctl start postgresql 2>/dev/null || true
          systemctl is-active postgresql >>/tmp/salt-states || true
          sleep 0.1
        done
      }

      upgrade() {
        systemctl stop postgresql
        block_postgres_start
        runuser -u postgres -- ${pg17}/bin/initdb --no-locale -E UTF8 -U postgres -D "$PGDATANEW"
        start_pid_lock_watcher
        systemd-run --unit=salt-sim --collect "$0" salt_sim
        cd /var/lib/postgresql
        runuser -u postgres -- ${pg17}/bin/pg_upgrade \
          --username=postgres \
          --old-datadir="$PGDATAOLD" --new-datadir="$PGDATANEW" \
          --old-bindir=${pg15}/bin --new-bindir=${pg17}/bin
        systemctl stop salt-sim
        assert_source_stayed_down
        unblock_postgres_start
      }

      "$@"
    '';
  };

  initOld = pkgs.pkgsLinux.writeShellApplication {
    name = "init-old";
    runtimeInputs = with pkgs.pkgsLinux; [
      coreutils
      util-linux
    ];
    text = ''
      if [ ! -f ${dataOld}/PG_VERSION ]; then
        install -d -o postgres -g postgres -m 0700 ${dataOld}
        runuser -u postgres -- ${pg15}/bin/initdb --no-locale -E UTF8 -U postgres -D ${dataOld}
      fi
    '';
  };
in
pkgs.testers.runNixOSTest {
  name = "pg-upgrade-start-guard";

  nodes.server = {
    virtualisation = {
      memorySize = 2048;
      diskSize = 4096;
    };

    users = {
      users.postgres = {
        isSystemUser = true;
        group = "postgres";
        home = "/var/lib/postgresql";
        createHome = true;
      };
      groups.postgres = { };
    };

    systemd.tmpfiles.rules = [ "d /run/postgresql 0755 postgres postgres -" ];

    systemd.services.postgresql = {
      wantedBy = [ "multi-user.target" ];
      serviceConfig = {
        Type = "notify";
        User = "postgres";
        Group = "postgres";
        ExecStartPre = "+${lib.getExe initOld}";
        ExecStart = "${pg15}/bin/postgres -D ${dataOld}";
        KillMode = "mixed";
        KillSignal = "SIGINT";
        Restart = "always";
        RestartSec = 1;
      };
    };
  };

  testScript = ''
    DRIVE = "${lib.getExe drive}"
    PG15 = "${pg15}/bin"
    PG17 = "${pg17}/bin"
    OLD = "${dataOld}"
    NEW = "${dataNew}"
    DROPIN = "/run/systemd/system/postgresql.service.d/pg-upgrade-lock.conf"

    def unit(name, job):
      server.succeed(f"systemd-run --unit={name} --collect {DRIVE} {job}")

    def kill(name):
      server.succeed(f"systemctl kill -s KILL {name}")
      server.wait_until_fails(f"systemctl is-active --quiet {name}")

    def pg_ctl(bindir, action, data, opts=""):
      log = "-l /tmp/pg_ctl.log" if action == "start" else ""
      return f"runuser -u postgres -- {bindir}/pg_ctl {action} -D {data} -w -s {log} {opts}"

    def sql(query, bindir=PG15, port=5432):
      return server.succeed(
        f"{bindir}/psql -h 127.0.0.1 -p {port} -U postgres -d postgres -Atc \"{query}\""
      ).strip()

    def show(prop):
      return server.succeed(f"systemctl show -p {prop} postgresql")

    start_all()
    server.wait_for_unit("postgresql.service")

    with subtest("Seed the source cluster"):
      sql("create table seed as select g as id, repeat(md5(g::text), 20) as pad from generate_series(1, 100000) g")
      expected = sql("select count(*) || ',' || sum(id) from seed")

    with subtest("Control: with no guard the start loop brings the source up"):
      server.succeed("systemctl stop postgresql")
      unit("salt-sim", "salt_sim")
      server.wait_until_succeeds("systemctl is-active --quiet postgresql", timeout=60)
      server.succeed("systemctl stop salt-sim")

    with subtest("A systemd start is refused while the block is held"):
      unit("hold-block", "hold_block")
      server.wait_until_succeeds("systemctl show -p ExecCondition postgresql | grep -q start-guard", timeout=120)
      server.fail("systemctl start postgresql")
      server.sleep(5)
      server.fail("systemctl is-active --quiet postgresql")
      assert "Restart=no" in show("Restart")

    with subtest("The block expires on its own when the holder is SIGKILLed"):
      kill("hold-block")
      server.succeed("systemctl start postgresql")
      server.wait_for_unit("postgresql.service")
      server.fail(f"test -e {DROPIN}")
      assert "Restart=always" in show("Restart")
      assert "NeedDaemonReload=no" in show("NeedDaemonReload")

    with subtest("The pid lock stops a direct start once the new cluster is up"):
      server.succeed("systemctl stop postgresql")
      unit("hold-lock", "hold_lock")
      server.wait_until_succeeds(f"test -s {OLD}/postmaster.pid", timeout=120)
      server.fail(pg_ctl(PG15, "start", OLD, "-t 5"))
      kill("hold-lock")
      server.succeed(pg_ctl(PG15, "start", OLD))
      server.succeed(pg_ctl(PG15, "stop", OLD))
      server.succeed("rm -f /run/pg-upgrade-source.pid")
      server.succeed("systemctl start postgresql")
      server.wait_for_unit("postgresql.service")

    with subtest("A real pg_upgrade copy under a start storm"):
      server.succeed(f"systemd-run --unit=fake-initiate --collect --pipe --wait {DRIVE} upgrade")
      attempts = int(server.succeed("wc -l </tmp/salt-states").strip())
      assert attempts >= 5, f"start loop barely ran: {attempts} attempts"
      server.fail("grep -qx active /tmp/salt-states")

    with subtest("The new cluster matches the seed"):
      server.succeed(pg_ctl(PG17, "start", NEW, "-o '-p 5433'"))
      assert sql("select count(*) || ',' || sum(id) from seed", PG17, 5433) == expected
      server.succeed(pg_ctl(PG17, "stop", NEW))
  '';
}
