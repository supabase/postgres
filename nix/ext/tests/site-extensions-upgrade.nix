# Real prestart -> site-extensions-update -> site-extensions profile path (PR #2324).
# Last subtest EXPECTED TO FAIL: nothing wires dynamic_library_path/extension_control_path
# to /nix/var/nix/profiles/site-extensions. MPG-12/#2424 wires a separate profile
# (site/pg-extensions, supautils only), not this one.
# Auto-registers as `ext-site-extensions-upgrade` in `nix flake check` — don't merge
# to develop until the gap above is fixed and the assertion holds.
# postgres_prestart.sh body below is copied from PR #2324's branch, not this repo's
# ansible/files/ (that PR hasn't merged). Switch to builtins.readFile once it does.
{ self, pkgs }:
let
  testLib = import ./lib.nix { inherit self pkgs; };
  inherit (pkgs) lib;
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;

  pinnedExtension = "pgaudit";
  pinnedVersion = "99.0"; # fake: distinguishable from any real pgaudit version

  # A throwaway package standing in for what the real catalog would resolve
  # pinnedExtension@pinnedVersion to — avoids coupling this test to the real
  # catalog's content-addressed hashes (which it can't fetch, the VM is
  # offline) and to the multi-GB real catalog build. The mechanism under
  # test (resolve -> nix-store -r -> nix-env --install) doesn't care what's
  # inside; the final assertion only needs postgres's real pgaudit untouched.
  placeholderPackage = pkgs.pkgsLinux.runCommand "pgaudit-${pinnedVersion}-generic" { } ''
    mkdir -p "$out/lib" "$out/share/postgresql/extension"
    echo "default_version = '${pinnedVersion}'" > "$out/share/postgresql/extension/pgaudit.control"
  '';
  fakeCatalog = pkgs.pkgsLinux.writeText "pg-extensions-catalog.json" (
    builtins.toJSON { ${pinnedExtension} = { ${pinnedVersion} = "${placeholderPackage}"; }; }
  );

  prestartScript = pkgs.pkgsLinux.writeShellScript "postgres-prestart-site-extensions" ''
    #!/bin/bash

    set -x  # Print commands

    log() {
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1"
    }

    handle_extension_versions() {
        local extensions_file="/etc/adminapi/pg-extensions.json"
        if [ ! -r "$extensions_file" ]; then
            log "extensions: no manifest at $extensions_file, skipping"
            return 0
        fi

        if site-extensions-update "$extensions_file"; then
            log "extensions: profile updated"
        else
            log "extensions: update failed, profile unchanged"
        fi
    }

    main() {
       log "Starting prestart script"

       # 1. Handle all extension versions from config file
       handle_extension_versions

       log "Prestart script completed"
    }

    # Initial locale setup
    if [ $(cat /etc/locale.gen | grep -c en_US.UTF-8) -eq 0 ]; then
       echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    fi

    if [ $(locale -a | grep -c en_US.utf8) -eq 0 ]; then
       locale-gen
    fi

    main
  '';
in
pkgs.testers.runNixOSTest {
  name = "site-extensions-upgrade";
  nodes.server = {
    imports = [ (testLib.makeSupabaseTestConfig { majorVersion = "17"; }) ];

    # systemd units don't inherit /run/current-system/sw/bin from systemPackages.
    environment.systemPackages = [ self.packages.${system}.site-extensions-update ];
    systemd.services.postgresql.path = [ self.packages.${system}.site-extensions-update ];
    systemd.services.postgresql.environment.PG_EXTENSIONS_CATALOG = "${fakeCatalog}";

    # VM has no network; placeholderPackage is a normal build input, so it's
    # already realized and gets copied in — no fetch needed at runtime.
    virtualisation.additionalPaths = [ placeholderPackage ];

    environment.etc."adminapi/pg-extensions.json".text = builtins.toJSON {
      ${pinnedExtension} = pinnedVersion;
    };

    # Matches prod: ExecStartPre=-+/usr/local/bin/postgres_prestart.sh (PR #2324).
    # Appended after the harness's own bootstrap ExecStartPre entries.
    systemd.services.postgresql.serviceConfig.ExecStartPre = lib.mkAfter [
      ("-+" + prestartScript)
    ];
  };

  testScript = ''
    pinned_extension = "${pinnedExtension}"
    pinned_version = "${pinnedVersion}"

    start_all()

    server.wait_for_unit("multi-user.target")
    server.wait_for_unit("postgresql.service")
    server.wait_for_unit("supabase-db-init.service")

    with subtest("extensions manifest present"):
      server.succeed("test -r /etc/adminapi/pg-extensions.json")

    with subtest("restart postgresql to trigger the real prestart path"):
      server.execute("systemctl restart postgresql.service")
      server.wait_for_unit("postgresql.service")

    with subtest("prestart ran site-extensions-update"):
      unit_log = server.succeed("journalctl -u postgresql.service -o cat --no-pager")
      assert "Starting prestart script" in unit_log, unit_log
      assert "extensions: profile updated" in unit_log, unit_log

    with subtest("site-extensions profile has the pinned version"):
      profile_contents = server.succeed(
        "nix-env --profile /nix/var/nix/profiles/site-extensions -q"
      ).strip()
      assert pinned_extension in profile_contents, profile_contents

    with subtest("EXPECTED TO FAIL: profile isn't on dynamic_library_path/extension_control_path"):
      default_version = server.succeed(
        "psql -U supabase_admin -d postgres -tAc "
        f"\"select default_version from pg_available_extensions where name = '{pinned_extension}'\""
      ).strip()
      assert default_version == pinned_version, f"expected {pinned_version}, got {default_version}"
  '';
}
