{
  runCommand,
  pgsqlSuperuser,
  psql_15,
}:
runCommand "start-postgres-replica" { } ''
  mkdir -p $out/bin
  substitute ${./start-replica.sh.in} $out/bin/start-postgres-replica \
    --subst-var-by 'PGSQL_SUPERUSER' '${pgsqlSuperuser}' \
    --subst-var-by 'PSQL15_BINDIR' '${psql_15}'
  chmod +x $out/bin/start-postgres-replica
''
