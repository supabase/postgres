# Last subtest EXPECTED TO FAIL until dynamic_library_path/extension_control_path
# point at /nix/var/nix/profiles/site-extensions. #2424 wires a different
# profile (site/pg-extensions, supautils only), not this one.
{ self, pkgs }:
let
  testLib = import ./lib.nix { inherit self pkgs; };
  inherit (pkgs) lib;
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;

  pinnedExtension = "pgaudit";
  pinnedVersion = "99.0";

  # Stands in for a real catalog entry, which the offline test VM can't fetch.
  placeholderPackage = pkgs.pkgsLinux.runCommand "pgaudit-${pinnedVersion}-generic" { } ''
    mkdir -p "$out/lib" "$out/share/postgresql/extension"
    echo "default_version = '${pinnedVersion}'" > "$out/share/postgresql/extension/pgaudit.control"
  '';
  fakeCatalog = pkgs.pkgsLinux.writeText "pg-extensions-catalog.json" (
    builtins.toJSON {
      ${pinnedExtension} = {
        ${pinnedVersion} = "${placeholderPackage}";
      };
    }
  );

  prestartScript = pkgs.pkgsLinux.writeShellScript "postgres-prestart-site-extensions" (
    builtins.readFile ../../../ansible/files/postgres_prestart.sh.j2
  );
in
pkgs.testers.runNixOSTest {
  name = "site-extensions-upgrade";
  nodes.server = {
    imports = [ (testLib.makeSupabaseTestConfig { majorVersion = "17"; }) ];

    # systemd units need their own PATH; update-site-extensions also expects
    # nix on PATH already, true on real hosts, not this VM.
    environment.systemPackages = [ self.packages.${system}.update-site-extensions ];
    systemd.services.postgresql.path = [
      self.packages.${system}.update-site-extensions
      pkgs.pkgsLinux.nix
    ];
    systemd.services.postgresql.environment.PG_EXTENSIONS_CATALOG = "${fakeCatalog}";

    # Pre-realize it: the VM has no network to fetch it at runtime.
    virtualisation.additionalPaths = [ placeholderPackage ];

    environment.etc."adminapi/pg-extensions.json".text = builtins.toJSON {
      ${pinnedExtension} = pinnedVersion;
    };

    systemd.services.postgresql.serviceConfig.ExecStartPre = lib.mkAfter [
      ("+" + prestartScript)
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

    with subtest("prestart ran update-site-extensions"):
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
