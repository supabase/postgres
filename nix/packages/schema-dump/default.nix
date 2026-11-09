{
  lib,
  runCommand,
  runtimeShell,
  writeText,
  dbmate,
  procps,
  stdenv,
  postgresql,
  startServer,
  version,
  port,
}:
let
  root = ../../..;
  migrationsDir = root + "/migrations/db";
  pgbouncerAuthSchemaSql = root + "/ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql";
  statExtensionSql = root + "/ansible/files/stat_extension.sql";

  script = writeText "schema-dump.sh" (
    lib.replaceStrings
      [
        "@port@"
        "@superuser@"
        "@migrationsDir@"
        "@system@"
        "@pgbouncerAuthSchemaSql@"
        "@statExtensionSql@"
        "@startServer@"
        "@postgresql@"
      ]
      [
        port
        "supabase_admin"
        "${migrationsDir}"
        stdenv.hostPlatform.system
        "${pgbouncerAuthSchemaSql}"
        "${statExtensionSql}"
        "${startServer}"
        "${postgresql}"
      ]
      (builtins.readFile ./schema-dump.sh)
  );
in
# Runs the init scripts and migrations through dbmate against a throwaway cluster and dumps the resulting schema.
# Does not depend on the committed migrations/schema-<version>.sql, so editing that file does not rerun postgres.
runCommand "schema-dump-${version}"
  {
    nativeBuildInputs = [
      dbmate
      postgresql
      procps
    ];
  }
  ''
    ${runtimeShell} -eu -o pipefail ${script} --version ${version} --port ${port}
  ''
