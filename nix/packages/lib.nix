{
  psql_17,
  psql_15,
  psql_orioledb-17,
  defaults,
  supabase-groonga,
  system,
  pgroonga,
}:
{
  makePostgresDevSetup =
    {
      pkgs,
      name,
      extraSubstitutions ? { },
    }:
    let
      paths = {
        migrationsDir = builtins.path {
          name = "migrations";
          path = ../../migrations/db;
        };
        postgresqlSchemaSql = builtins.path {
          name = "postgresql-schema";
          path = ../tools/postgresql_schema.sql;
        };
        pgbouncerAuthSchemaSql = builtins.path {
          name = "pgbouncer-auth-schema";
          path = ../../ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql;
        };
        statExtensionSql = builtins.path {
          name = "stat-extension";
          path = ../../ansible/files/stat_extension.sql;
        };
        pgconfigFile = builtins.path {
          name = "postgresql.conf";
          path = ../../ansible/files/postgresql_config/postgresql.conf.j2;
        };
        configConfDir = builtins.path {
          name = "conf.d";
          path = ../../ansible/files/postgresql_config/conf.d;
        };
        pgHbaConfigFile = builtins.path {
          name = "pg_hba.conf";
          path = ../../ansible/files/postgresql_config/pg_hba.conf.j2;
        };
        pgIdentConfigFile = builtins.path {
          name = "pg_ident.conf";
          path = ../../ansible/files/postgresql_config/pg_ident.conf.j2;
        };
        postgresqlExtensionCustomScriptsPath = builtins.path {
          name = "extension-custom-scripts";
          path = ../../ansible/files/postgresql_extension_custom_scripts;
        };
        getkeyScript = builtins.path {
          name = "pgsodium_getkey.sh";
          path = ../tests/util/pgsodium_getkey.sh;
        };
      };

      localeArchive =
        if pkgs.stdenv.isDarwin then
          "${pkgs.darwin.locale}/share/locale"
        else
          "${pkgs.glibcLocales}/lib/locale/locale-archive";

      postgresqlConfigBaseDir = builtins.path {
        name = "postgresql_config";
        path = ../../ansible/files/postgresql_config;
      };

      substitutions = {
        SHELL_PATH = "${pkgs.bash}/bin/bash";
        PGSQL_DEFAULT_PORT = "${defaults.port}";
        PGSQL_SUPERUSER = "${defaults.superuser}";
        PSQL15_BINDIR = "${psql_15}";
        PSQL17_BINDIR = "${psql_17}";
        PSQL_CONF_FILE = "${paths.pgconfigFile}";
        POSTGRESQL_CONFIG_DIR = "${postgresqlConfigBaseDir}";
        PSQLORIOLEDB17_BINDIR = "${psql_orioledb-17}";
        PGSODIUM_GETKEY = "${paths.getkeyScript}";
        PG_HBA = "${paths.pgHbaConfigFile}";
        PG_IDENT = "${paths.pgIdentConfigFile}";
        LOCALES = "${localeArchive}";
        EXTENSION_CUSTOM_SCRIPTS_DIR = "${paths.postgresqlExtensionCustomScriptsPath}";
        MECAB_LIB = "${pgroonga}/lib/groonga/plugins/tokenizers/tokenizer_mecab.so";
        GROONGA_DIR = "${supabase-groonga}";
        MIGRATIONS_DIR = "${paths.migrationsDir}";
        POSTGRESQL_SCHEMA_SQL = "${paths.postgresqlSchemaSql}";
        PGBOUNCER_AUTH_SCHEMA_SQL = "${paths.pgbouncerAuthSchemaSql}";
        STAT_EXTENSION_SQL = "${paths.statExtensionSql}";
        CURRENT_SYSTEM = "${system}";
      } // extraSubstitutions; # Merge in any extra substitutions
    in
    pkgs.runCommand name
      {
        inherit (paths)
          migrationsDir
          postgresqlSchemaSql
          pgbouncerAuthSchemaSql
          statExtensionSql
          ;
      }
      ''
        mkdir -p $out/bin

        substitute ${../tools/run-server.sh.in} $out/bin/start-postgres-server \
          ${
            builtins.concatStringsSep " " (
              builtins.attrValues (
                builtins.mapAttrs (name: value: "--subst-var-by '${name}' '${value}'") substitutions
              )
            )
          }
        chmod +x $out/bin/start-postgres-server
      '';
}
