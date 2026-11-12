{
  runCommand,
  version,
  schemaDump,
}:
let
  committed = ../../../migrations/schema-${version}.sql;
in
# Fails when the committed schema differs from what the migrations produce.
runCommand "schema-check-${version}" { } ''
  if ! diff -u ${committed} ${schemaDump}/schema.sql; then
    echo "migrations/schema-${version}.sql is out of date, regenerate it with: nix run .#dbmate-tool -- --version ${version}" >&2
    exit 1
  fi
  touch $out
''
