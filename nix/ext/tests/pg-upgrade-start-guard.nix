{ self, pkgs }:
let
  inherit (pkgs) lib;
  lpkgs = pkgs.pkgsLinux;
  system = lpkgs.stdenv.hostPlatform.system;

  pg15 = self.packages.${system}."psql_15/bin";
  pg17 = self.packages.${system}."psql_17/bin";

  dataOld = "/var/lib/postgresql/data";
  dataNew = "/var/lib/postgresql/data-17";
  dropIn = "/run/systemd/system/postgresql.service.d/pg-upgrade-lock.conf";

  initiate = builtins.path {
    path = ../../../ansible/files/admin_api_scripts/pg_upgrade_scripts/initiate.sh;
    name = "initiate.sh";
  };

  # initiate.sh runs the upgrade when sourced, so extract only the guard.
  startGuard = lpkgs.runCommand "start-guard.sh" { } ''
    awk '
      /^PG_UPGRADE_(LOCK|PID|INITIATE|START)_[A-Z_]+=/ { print }
      /^(block_postgres_start|start_pid_lock_watcher|unblock_postgres_start|assert_source_stayed_down)\(\) \{/ { printing = 1 }
      printing { print }
      printing && /^}/ { printing = 0 }
    ' ${initiate} >$out
  '';

  guardEnv = lpkgs.writeText "guard-env.sh" ''
    export PATH=${
      lib.makeBinPath (
        with lpkgs;
        [
          bash
          coreutils
          diffutils
          gnugrep
          gnused
          procps
          systemd
          util-linux
        ]
      )
    }
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
    . ${startGuard}
  '';

  holdBlock = lpkgs.writeShellScript "hold-block" ''
    set -eEuo pipefail
    . ${guardEnv}
    systemctl stop postgresql
    block_postgres_start
    exec sleep infinity
  '';

  saltSim = lpkgs.writeShellScript "salt-sim" ''
    export PATH=${
      lib.makeBinPath [
        lpkgs.coreutils
        lpkgs.systemd
      ]
    }
    : >/tmp/salt-states
    while :; do
      systemctl start postgresql 2>/dev/null || true
      systemctl is-active postgresql >>/tmp/salt-states || true
      sleep 0.1
    done
  '';

  holdLock = lpkgs.writeShellScript "hold-lock" ''
    set -eEuo pipefail
    . ${guardEnv}
    PGDATANEW=/tmp/fake-new
    mkdir -p "$PGDATANEW"
    runuser -u postgres -- bash -c 'sleep infinity; true' fake-pg-upgrade "--old-datadir=$PGDATAOLD" &
    start_pid_lock_watcher
    touch "$PGDATANEW/postmaster.pid"
    wait
  '';

  guardedUpgrade = lpkgs.writeShellScript "guarded-upgrade" ''
    set -eEuo pipefail
    . ${guardEnv}
    systemctl stop postgresql
    block_postgres_start
    runuser -u postgres -- ${pg17}/bin/initdb --no-locale -E UTF8 -U postgres -D "$PGDATANEW"
    start_pid_lock_watcher
    systemd-run --unit=salt-sim --collect ${saltSim}
    cd /var/lib/postgresql
    runuser -u postgres -- ${pg17}/bin/pg_upgrade \
      --username=postgres \
      --old-datadir="$PGDATAOLD" --new-datadir="$PGDATANEW" \
      --old-bindir=${pg15}/bin --new-bindir=${pg17}/bin
    systemctl stop salt-sim
    assert_source_stayed_down
    unblock_postgres_start
  '';

  initOld = lpkgs.writeShellScript "init-old" ''
    set -euo pipefail
    if [ ! -f ${dataOld}/PG_VERSION ]; then
      ${lpkgs.coreutils}/bin/install -d -o postgres -g postgres -m 0700 ${dataOld}
      ${lpkgs.util-linux}/bin/runuser -u postgres -- \
        ${pg15}/bin/initdb --no-locale -E UTF8 -U postgres -D ${dataOld}
    fi
  '';
in
pkgs.testers.runNixOSTest {
  name = "pg-upgrade-start-guard";
  nodes.server =
    { ... }:
    {
      virtualisation.memorySize = 2048;
      virtualisation.diskSize = 4096;

      users.users.postgres = {
        isSystemUser = true;
        group = "postgres";
        home = "/var/lib/postgresql";
        createHome = true;
      };
      users.groups.postgres = { };
      systemd.tmpfiles.rules = [ "d /run/postgresql 0755 postgres postgres -" ];

      systemd.services.postgresql = {
        wantedBy = [ "multi-user.target" ];
        serviceConfig = {
          Type = "notify";
          User = "postgres";
          Group = "postgres";
          ExecStartPre = "+${initOld}";
          ExecStart = "${pg15}/bin/postgres -D ${dataOld}";
          KillMode = "mixed";
          KillSignal = "SIGINT";
          Restart = "always";
          RestartSec = 1;
        };
      };
    };

  testScript = ''
    PG15 = "${pg15}/bin"
    PG17 = "${pg17}/bin"
    DROPIN = "${dropIn}"

    def sql(query, port=5432, bindir=PG15):
      return server.succeed(
        f"{bindir}/psql -h 127.0.0.1 -p {port} -U postgres -d postgres -Atc \"{query}\""
      ).strip()

    start_all()
    server.wait_for_unit("postgresql.service")

    with subtest("Seed the source cluster"):
      sql("create table seed as select g as id, repeat(md5(g::text), 20) as pad from generate_series(1, 400000) g")
      expected = sql("select count(*) || ',' || sum(id) from seed")

    with subtest("Control: with no guard the start loop brings the source up"):
      server.succeed("systemctl stop postgresql")
      server.succeed("systemd-run --unit=salt-sim --collect ${saltSim}")
      server.wait_until_succeeds("systemctl is-active --quiet postgresql", timeout=30)
      server.succeed("systemctl stop salt-sim")

    with subtest("A systemd start is refused while the block is held"):
      server.succeed("systemd-run --unit=hold-block --collect ${holdBlock}")
      server.wait_until_succeeds("systemctl show -p ExecCondition postgresql | grep -q start-guard", timeout=120)
      server.fail("systemctl start postgresql")
      server.sleep(5)
      server.fail("systemctl is-active --quiet postgresql")
      assert "Restart=no" in server.succeed("systemctl show -p Restart postgresql")

    with subtest("The block expires on its own when the holder is SIGKILLed"):
      server.succeed("systemctl kill -s KILL hold-block")
      server.wait_until_fails("systemctl is-active --quiet hold-block")
      server.succeed("systemctl start postgresql")
      server.wait_for_unit("postgresql.service")
      server.fail(f"test -e {DROPIN}")
      assert "Restart=always" in server.succeed("systemctl show -p Restart postgresql")
      assert "NeedDaemonReload=no" in server.succeed("systemctl show -p NeedDaemonReload postgresql")

    with subtest("The pid lock stops a direct start once the new cluster is up"):
      server.succeed("systemctl stop postgresql")
      server.succeed("systemd-run --unit=hold-lock --collect ${holdLock}")
      server.wait_until_succeeds("test -s ${dataOld}/postmaster.pid", timeout=120)
      server.fail(f"runuser -u postgres -- {PG15}/pg_ctl start -D ${dataOld} -w -t 5 -s -l /tmp/pg15-locked.log")
      server.succeed("systemctl kill -s KILL hold-lock")
      server.wait_until_fails("systemctl is-active --quiet hold-lock")
      server.succeed(f"runuser -u postgres -- {PG15}/pg_ctl start -D ${dataOld} -w -s -l /tmp/pg15.log")
      server.succeed(f"runuser -u postgres -- {PG15}/pg_ctl stop -D ${dataOld} -w -s")
      server.succeed("rm -f /run/pg-upgrade-source.pid")
      server.succeed("systemctl start postgresql")
      server.wait_for_unit("postgresql.service")

    with subtest("A real pg_upgrade copy under a start storm"):
      server.succeed("systemd-run --unit=fake-initiate --collect --pipe --wait ${guardedUpgrade}")
      attempts = int(server.succeed("wc -l </tmp/salt-states").strip())
      assert attempts >= 5, f"start loop barely ran: {attempts} attempts"
      server.fail("grep -qx active /tmp/salt-states")

    with subtest("The new cluster matches the seed"):
      server.succeed(
        f"runuser -u postgres -- {PG17}/pg_ctl start -D ${dataNew} -w -s -l /tmp/pg17.log -o '-p 5433'"
      )
      assert sql("select count(*) || ',' || sum(id) from seed", port=5433, bindir=PG17) == expected
      server.succeed(f"runuser -u postgres -- {PG17}/pg_ctl stop -D ${dataNew} -w -s")

    with subtest("The source is untouched and starts again"):
      server.succeed("systemctl start postgresql")
      server.wait_for_unit("postgresql.service")
      assert sql("select count(*) || ',' || sum(id) from seed") == expected
      server.fail(f"test -e {DROPIN}")
  '';
}
