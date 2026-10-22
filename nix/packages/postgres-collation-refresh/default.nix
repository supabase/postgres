{
  lib,
  stdenv,
  runCommand,
  replaceVars,
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
runCommand "postgres-collation-refresh" { } ''
  install -Dm0644 ${
    replaceVars ./postgres-collation-refresh.sql { inherit minGlibc maxGlibc; }
  } $out/share/postgres-collation-refresh.sql
  install -Dm0644 ${./postgresql-collation-refresh.service} $out/lib/systemd/system/postgresql-collation-refresh.service
''
