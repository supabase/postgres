{
  lib,
  stdenv,
  writeShellApplication,
  writeTextDir,
  symlinkJoin,
  coreutils,
}:
let
  minGlibc = "2.31";
  maxGlibc = "2.44";

  script = writeShellApplication {
    name = "postgres_collation_refresh";
    runtimeInputs = [ coreutils ];
    runtimeEnv = {
      MIN_GLIBC = minGlibc;
      MAX_GLIBC = maxGlibc;
    };
    text = builtins.readFile ./postgres-collation-refresh.sh;
  };

  unit = writeTextDir "lib/systemd/system/postgresql-collation-refresh.service" ''
    [Unit]
    Description=Refresh default collation version
    After=postgresql.service
    PartOf=postgresql.service

    [Service]
    Type=oneshot
    RemainAfterExit=yes
    User=postgres
    TimeoutStartSec=120
    Environment=PATH=/var/lib/postgresql/.nix-profile/bin
    ExecStart=${lib.getExe script}
  '';
in
assert lib.assertMsg
  (
    !stdenv.hostPlatform.isGnu
    || lib.versionAtLeast maxGlibc (lib.versions.majorMinor stdenv.cc.libc.version)
  )
  "glibc ${stdenv.cc.libc.version} is above the reviewed maximum ${maxGlibc}. Review English collation changes, then raise maxGlibc in nix/packages/postgres-collation-refresh.nix.";
symlinkJoin {
  name = "postgres-collation-refresh";
  paths = [
    script
    unit
  ];
}
