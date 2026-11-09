{
  lib,
  writeShellApplication,
  overmind,
  dbmate,
  nix,
  jq,
  yq,
  system,
  defaults,
}:
let
  root = ../../..;
  migrationsDir = root + "/migrations/db";
  ansibleVars = root + "/ansible/vars.yml";
  pgbouncerAuthSchemaSql = root + "/ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql";
  statExtensionSql = root + "/ansible/files/stat_extension.sql";
in
writeShellApplication {
  name = "dbmate-tool";
  runtimeInputs = [
    overmind
    dbmate
    nix
    jq
    yq
  ];
  text =
    lib.replaceStrings
      [
        "@port@"
        "@superuser@"
        "@migrationsDir@"
        "@system@"
        "@ansibleVars@"
        "@pgbouncerAuthSchemaSql@"
        "@statExtensionSql@"
      ]
      [
        defaults.port
        defaults.superuser
        "${migrationsDir}"
        system
        "${ansibleVars}"
        "${pgbouncerAuthSchemaSql}"
        "${statExtensionSql}"
      ]
      (builtins.readFile ./dbmate-tool.sh);
}
