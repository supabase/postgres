{
  dbmate,
  defaults,
  postgresql,
  runCommand,
  runtimeShell,
  port,
  startServer,
  version,
}:
let
  root = ../../..;
  migrations = root + "/migrations/db";
  pgbouncerAuthSchemaSQL = root + "/ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql";
  statExtensionSQL = root + "/ansible/files/stat_extension.sql";
in
# Runs the init scripts and migrations through dbmate against a throwaway cluster and dumps the resulting schema.
# Does not depend on the committed migrations/schema-<version>.sql, so editing that file does not rerun postgres.
runCommand "schema-dump-${version}"
  {
    nativeBuildInputs = [
      dbmate
      postgresql
      startServer
    ];

    # libpq reads these, so none of the pg tools need connection flags
    PGDATABASE = "postgres";
    PGHOST = defaults.host;
    PGPORT = port;
    PGUSER = defaults.superuser;
  }
  ''
    ${runtimeShell} ${./schema-dump.sh} ${version} ${migrations} ${pgbouncerAuthSchemaSQL} ${statExtensionSQL}
  ''
