{
  lib,
  stdenv,
  writeShellApplication,
  runCommand,
  symlinkJoin,
  coreutils,
}:
let
  minGlibc = "2.31";
  maxGlibc = "2.44";
in
assert lib.assertMsg
  (
    !stdenv.hostPlatform.isGnu
    || lib.versionAtLeast maxGlibc (lib.versions.majorMinor stdenv.cc.libc.version)
  )
  "glibc ${stdenv.cc.libc.version} is above the reviewed maximum ${maxGlibc}. Review English collation changes, then raise maxGlibc in nix/packages/postgres-collation-refresh/default.nix.";
let
  script = writeShellApplication {
    name = "postgres_collation_refresh";
    runtimeInputs = [ coreutils ];
    runtimeEnv = {
      MIN_GLIBC = minGlibc;
      MAX_GLIBC = maxGlibc;
    };
    text = builtins.readFile ./postgres-collation-refresh.sh;
  };
in
symlinkJoin {
  name = "postgres-collation-refresh";
  paths = [
    script
    (runCommand "postgres-collation-refresh-unit" { } ''
      install -Dm0644 ${./postgresql-collation-refresh.service} $out/lib/systemd/system/postgresql-collation-refresh.service
    '')
  ];
}
