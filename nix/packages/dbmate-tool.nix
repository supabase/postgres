{ pkgs, system }:
let
  migrationsDir = ../../migrations/db;
  ansibleVars = ../../ansible/vars.yml;
  pgbouncerAuthSchemaSql = ../../ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql;
  statExtensionSql = ../../ansible/files/stat_extension.sql;
  pgsqlDefaultPort = "5435";
  pgsqlSuperuser = "supabase_admin";
in
pkgs.runCommand "dbmate-tool"
  {
    buildInputs = with pkgs; [
      overmind
      dbmate
      nix
      jq
      yq
    ];
    nativeBuildInputs = with pkgs; [
      makeWrapper
    ];
  }
  ''
    mkdir -p $out/bin $out/migrations
    cp -r ${migrationsDir}/* $out
    substitute ${../tools/dbmate-tool.sh.in} $out/bin/dbmate-tool \
      --subst-var-by 'PGSQL_DEFAULT_PORT' '${pgsqlDefaultPort}' \
      --subst-var-by 'MIGRATIONS_DIR' $out \
      --subst-var-by 'PGSQL_SUPERUSER' '${pgsqlSuperuser}' \
      --subst-var-by 'ANSIBLE_VARS' ${ansibleVars} \
      --subst-var-by 'CURRENT_SYSTEM' '${system}' \
      --subst-var-by 'PGBOUNCER_AUTH_SCHEMA_SQL' '${pgbouncerAuthSchemaSql}' \
      --subst-var-by 'STAT_EXTENSION_SQL' '${statExtensionSql}'
    chmod +x $out/bin/dbmate-tool
    wrapProgram $out/bin/dbmate-tool \
      --prefix PATH : ${
        pkgs.lib.makeBinPath [
          pkgs.overmind
          pkgs.dbmate
          pkgs.nix
          pkgs.jq
          pkgs.yq
        ]
      }
  ''
