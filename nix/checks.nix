{ self, ... }:
{
  perSystem =
    {
      self',
      system,
      pkgs,
      lib,
      ...
    }:
    let
      pkgs-lib = pkgs.callPackage ./packages/lib.nix {
        psql_15 = self'.packages."psql_15/bin";
        psql_17 = self'.packages."psql_17/bin";
        psql_orioledb-17 = self'.packages."psql_orioledb-17/bin";
        inherit (self.supabase) defaults;
      };
      bashlog = builtins.fetchurl {
        url = "https://raw.githubusercontent.com/Zordrak/bashlog/master/log.sh";
        sha256 = "1vrjcbzls0ba2qkg7ffddz2gxqn2rlj3wyvril2gz0mfi89y9vk9";
      };
    in
    {
      checks =
        let
          # Create a testing harness for a PostgreSQL package. This is used for
          # 'nix flake check', and works with any PostgreSQL package you hand it.
          # deadnix: skip
          makeCheckHarness =
            pgpkg:
            let
              pg_prove = pkgs.perlPackages.TAPParserSourceHandlerpgTAP;
              inherit (self'.packages) pg_regress;
              getkey-script = pkgs.stdenv.mkDerivation {
                name = "pgsodium-getkey";
                buildCommand = ''
                  mkdir -p $out/bin
                  cat > $out/bin/pgsodium-getkey << 'EOF'
                  #!${pkgs.bash}/bin/bash
                  set -euo pipefail

                  TMPDIR_BASE=$(mktemp -d)

                  KEY_DIR="''${PGSODIUM_KEY_DIR:-$TMPDIR_BASE/pgsodium}"
                  KEY_FILE="$KEY_DIR/pgsodium.key"

                  if ! mkdir -p "$KEY_DIR" 2>/dev/null; then
                    echo "Error: Could not create key directory $KEY_DIR" >&2
                    exit 1
                  fi
                  chmod 1777 "$KEY_DIR"

                  if [[ ! -f "$KEY_FILE" ]]; then
                    if ! (dd if=/dev/urandom bs=32 count=1 2>/dev/null | od -A n -t x1 | tr -d ' \n' > "$KEY_FILE"); then
                      if ! (openssl rand -hex 32 > "$KEY_FILE"); then
                        echo "00000000000000000000000000000000" > "$KEY_FILE"
                        echo "Warning: Using fallback key" >&2
                      fi
                    fi
                    chmod 644 "$KEY_FILE"
                  fi

                  if [[ -f "$KEY_FILE" && -r "$KEY_FILE" ]]; then
                    cat "$KEY_FILE"
                  else
                    echo "Error: Cannot read key file $KEY_FILE" >&2
                    exit 1
                  fi
                  EOF
                  chmod +x $out/bin/pgsodium-getkey
                '';
              };

              # Get the major version for filtering
              majorVersion =
                let
                  version = builtins.trace "pgpkg.version is: ${pgpkg.version}" pgpkg.version;
                  isOrioledbMatch = builtins.match "^17_[0-9]+$" version != null;
                  isSeventeenMatch = builtins.match "^17[.][0-9]+$" version != null;
                  result =
                    if isOrioledbMatch then
                      "orioledb-17"
                    else if isSeventeenMatch then
                      "17"
                    else
                      "15";
                in
                builtins.trace "Major version result: ${result}" result;

              # Select the appropriate pgroonga package for this PostgreSQL version
              pgroonga = self'.legacyPackages."psql_${majorVersion}".exts.pgroonga;

              pgPort =
                if (majorVersion == "17") then
                  "5535"
                else if (majorVersion == "15") then
                  "5536"
                else
                  "5537";

              # Use the shared setup but with a test-specific name
              start-postgres-server-bin = pkgs-lib.makePostgresDevSetup {
                inherit pkgs pgroonga;
                name = "start-postgres-server-test";
                extraSubstitutions = {
                  PGSODIUM_GETKEY = "${getkey-script}/bin/pgsodium-getkey";
                  PGSQL_DEFAULT_PORT = pgPort;
                };
              };

              getVersionArg =
                pkg:
                let
                  name = pkg.version;
                in
                # Check orioledb first since "17_15" would match "17.*" pattern
                if builtins.match "17_[0-9]+" name != null then
                  "orioledb-17"
                else if builtins.match "15.*" name != null then
                  "15"
                else if builtins.match "17.*" name != null then
                  "17"
                else
                  throw "Unsupported PostgreSQL version: ${name}";

              # Tests to skip for OrioleDB (not compatible with OrioleDB storage)
              orioledbSkipTests = [
                "index_advisor" # index_advisor doesn't support OrioleDB tables
              ];

              # Helper function to filter SQL files based on version
              filterTestFiles =
                version: dir:
                let
                  files = builtins.readDir dir;
                  # Get list of OrioleDB-specific test basenames , then strip the orioledb prefix from them
                  orioledbVariants = pkgs.lib.pipe files [
                    builtins.attrNames
                    (builtins.filter (n: builtins.match "z_orioledb-17_.*\\.sql" n != null))
                    (map (n: builtins.substring 14 (pkgs.lib.stringLength n - 18) n)) # Remove "z_orioledb-17_" prefix (14 chars) and ".sql" suffix (4 chars)
                  ];
                  hasOrioledbVariant = basename: builtins.elem basename orioledbVariants;
                  isValidFile =
                    name:
                    let
                      isVersionSpecific = builtins.match "z_.*" name != null;
                      basename = builtins.substring 0 (pkgs.lib.stringLength name - 4) name; # Remove .sql
                      # Skip tests that don't work with OrioleDB
                      isSkippedForOrioledb = version == "orioledb-17" && builtins.elem basename orioledbSkipTests;
                      matchesVersion =
                        if isSkippedForOrioledb then
                          false
                        else if isVersionSpecific then
                          if version == "orioledb-17" then
                            builtins.match "z_orioledb-17_.*" name != null
                          else if version == "17" then
                            builtins.match "z_17_.*" name != null
                          else
                            builtins.match "z_15_.*" name != null
                        else
                        # For common tests: exclude if OrioleDB variant exists and we're running OrioleDB
                        if version == "orioledb-17" && hasOrioledbVariant basename then
                          false
                        else
                          true;
                    in
                    pkgs.lib.hasSuffix ".sql" name && matchesVersion;
                in
                pkgs.lib.filterAttrs (name: _: isValidFile name) files;

              # Filter SQL test files
              filteredSqlTests = filterTestFiles majorVersion ./tests/sql;

              # Convert filtered tests to a sorted list of basenames (without extension)
              testList = pkgs.lib.mapAttrsToList (
                name: _: builtins.substring 0 (pkgs.lib.stringLength name - 4) name
              ) filteredSqlTests;
              sortedTestList = builtins.sort (a: b: a < b) testList;
            in
            pkgs.writeShellApplication rec {
              name = "postgres-${pgpkg.version}-check-harness";
              bashOptions = [
                "nounset"
                "pipefail"
              ];
              runtimeInputs = with pkgs; [
                coreutils
                bash
                perl
                pgpkg
                pg_prove
                pg_regress
                procps
                start-postgres-server-bin
                which
                getkey-script
                supabase-groonga
                python3
                netcat
              ];

              text = ''

                #shellcheck disable=SC1091
                source ${bashlog}
                #shellcheck disable=SC1091
                source ${pkgs.stdenv}/setup
                export PATH="${lib.makeBinPath runtimeInputs}:$PATH"

                export BASHLOG_FILE=1
                export BASHLOG_FILE_PATH=debug.log
                # Use a build-specific directory for coordination
                BUILD_TMP=$(mktemp -d)

                # Function to log command execution with stdout and stderr
                function log_cmd {
                  local cmd_name="$1"
                  shift
                  log debug "Executing: $cmd_name $*"
                  local exit_code=0
                  echo "\$ $cmd_name $*" >> debug.log

                  "$cmd_name" "$@" >> debug.log 2>&1 || exit_code=$?
                  log debug "Exit code: $exit_code"
                  return $exit_code
                }

                function on_exit {
                  local exit_code=$?
                  kill $HTTP_MOCK_PID 2>/dev/null || true
                  rm -rf "$BUILD_TMP"
                  if [ $exit_code -ne 0 ]; then
                    log error "An error occurred. Exit code: $exit_code"
                    log error "Debug logs:"
                    cat debug.log || log error "No debug.log file found"
                  fi
                }
                trap on_exit EXIT
                trap "" DEBUG

                function check_postgres_ready {
                  for i in {1..60}; do
                      if log_cmd pg_isready -h localhost -p ${pgPort} -U supabase_admin -q; then
                          log info "PostgreSQL is ready"
                          break
                      fi
                      sleep 1
                      if [ "$i" -eq 60 ]; then
                          log error "PostgreSQL failed to start"
                          exit 1
                      fi
                  done
                }

                # Start HTTP mock server for http extension tests
                HTTP_MOCK_PORT_FILE="$BUILD_TMP/http-mock-port"

                log info "Starting HTTP mock server (will find free port)..."
                HTTP_MOCK_PORT_FILE="$HTTP_MOCK_PORT_FILE" log_cmd ${pkgs.python3}/bin/python3 ${./tests/http-mock-server.py} &
                HTTP_MOCK_PID=$!

                # Clean up on exit

                # Wait for server to start and write port file
                for i in {1..10}; do
                  if [ -f "$HTTP_MOCK_PORT_FILE" ]; then
                    HTTP_MOCK_PORT=$(cat "$HTTP_MOCK_PORT_FILE")
                    log info "HTTP mock server started on port $HTTP_MOCK_PORT"
                    break
                  fi
                  sleep 1
                done

                if [ ! -f "$HTTP_MOCK_PORT_FILE" ]; then
                  log error "Failed to start HTTP mock server"
                  exit 1
                fi

                # Export the port for use in SQL tests
                export HTTP_MOCK_PORT

                #First we need to create a generic pg cluster for pgtap tests and run those
                export GRN_PLUGINS_DIR=${pkgs.supabase-groonga}/lib/groonga/plugins
                PGTAP_CLUSTER=$(mktemp -d)
                log info "Creating temporary PostgreSQL cluster at $PGTAP_CLUSTER"
                log_cmd initdb --locale=C --username=supabase_admin -D "$PGTAP_CLUSTER"
                substitute ${./tests/postgresql.conf.in} "$PGTAP_CLUSTER"/postgresql.conf \
                  --subst-var-by PGSODIUM_GETKEY_SCRIPT "${getkey-script}/bin/pgsodium-getkey"
                echo "listen_addresses = '127.0.0.1'" >> "$PGTAP_CLUSTER"/postgresql.conf
                echo "port = ${pgPort}" >> "$PGTAP_CLUSTER"/postgresql.conf
                echo "host all all 127.0.0.1/32 trust" >> "$PGTAP_CLUSTER/pg_hba.conf"
                log info "Checking shared_preload_libraries setting:"
                log info "$(grep -rn "shared_preload_libraries" "$PGTAP_CLUSTER"/postgresql.conf)"
                # Remove timescaledb if running orioledb-17 check
                log info "pgpkg.version is: ${pgpkg.version}"
                #shellcheck disable=SC2193
                if [[ "${pgpkg.version}" == *"17"* ]]; then
                  perl -pi -e 's/ timescaledb,//g' "$PGTAP_CLUSTER/postgresql.conf"
                fi
                # Configure OrioleDB if running orioledb-17 check
                #shellcheck disable=SC2193
                if [[ "${pgpkg.version}" == *"_"* ]]; then
                  log info "Configuring OrioleDB..."
                  # Add orioledb to shared_preload_libraries
                  perl -pi -e "s/(shared_preload_libraries = ')/\$1orioledb, /" "$PGTAP_CLUSTER/postgresql.conf"
                  log info "OrioleDB added to shared_preload_libraries"
                fi

                # Check if postgresql.conf exists
                if [ ! -f "$PGTAP_CLUSTER/postgresql.conf" ]; then
                    log error "postgresql.conf is missing!"
                    exit 1
                fi

                # PostgreSQL startup
                if [[ "$(uname)" == "Darwin" ]]; then
                log_cmd pg_ctl -D "$PGTAP_CLUSTER" -l "$PGTAP_CLUSTER/postgresql.log" -o "-k $PGTAP_CLUSTER -p ${pgPort} -d 5" start
                else
                mkdir -p "$PGTAP_CLUSTER/sockets"
                log_cmd pg_ctl -D "$PGTAP_CLUSTER" -l "$PGTAP_CLUSTER/postgresql.log" -o "-k $PGTAP_CLUSTER/sockets -p ${pgPort} -d 5" start
                fi || {
                log error "pg_ctl failed to start PostgreSQL"
                log error "Contents of postgresql.log:"
                cat "$PGTAP_CLUSTER"/postgresql.log
                exit 1
                }

                log info "Waiting for PostgreSQL to be ready..."
                check_postgres_ready

                log info "Creating test database"
                log_cmd createdb -p ${pgPort} -h localhost --username=supabase_admin testing

                # Create orioledb extension if running orioledb-17 check (before prime.sql)
                #shellcheck disable=SC2193
                if [[ "${pgpkg.version}" == *"_"* ]]; then
                  log info "Creating orioledb extension..."
                  log_cmd psql -p ${pgPort} -h localhost --username=supabase_admin -d testing -c "CREATE EXTENSION IF NOT EXISTS orioledb;"
                fi

                log info "Loading prime SQL file"
                if ! log_cmd psql -p ${pgPort} -h localhost --username=supabase_admin -d testing -v ON_ERROR_STOP=1 -Xf ${./tests/prime.sql}; then
                  log error "Error executing SQL file. PostgreSQL log content:"
                  cat "$PGTAP_CLUSTER"/postgresql.log
                  pg_ctl -D "$PGTAP_CLUSTER" stop
                  exit 1
                fi

                # Create a table to store test configuration
                log info "Creating test_config table"
                log_cmd psql -p ${pgPort} -h localhost --username=supabase_admin -d testing -c "
                  CREATE TABLE IF NOT EXISTS test_config (key TEXT PRIMARY KEY, value TEXT);
                  INSERT INTO test_config (key, value) VALUES ('http_mock_port', '$HTTP_MOCK_PORT')
                  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
                "
                SORTED_DIR=$(mktemp -d)
                for t in $(printf "%s\n" ${builtins.concatStringsSep " " sortedTestList}); do
                  log info "Running pgtap test: $t.sql"
                  #XXX enable ON_ERROR_STOP ?
                  log_cmd psql -p ${pgPort} -h localhost --username=supabase_admin -d testing -f "${./tests/sql}/$t.sql"
                done
                rm -rf "$SORTED_DIR"
                log_cmd pg_ctl -D "$PGTAP_CLUSTER" stop
                rm -rf "$PGTAP_CLUSTER"

                # End of pgtap tests
                # from here on out we are running pg_regress tests, we use a different cluster for this
                # which is start by the start-postgres-server-bin script
                # start-postgres-server-bin script closely matches our AMI setup, configurations and migrations

                log info "Starting PostgreSQL server for pg_regress tests"
                unset GRN_PLUGINS_DIR
                if ! log_cmd ${start-postgres-server-bin}/bin/start-postgres-server ${getVersionArg pgpkg} --daemonize; then
                  log error "Failed to start PostgreSQL server for pg_regress tests"
                  exit 1
                fi

                check_postgres_ready

                # Create orioledb extension if running orioledb-17 check (before prime.sql)
                #shellcheck disable=SC2193
                if [[ "${pgpkg.version}" == *"_"* ]]; then
                  log info "Creating orioledb extension for pg_regress tests..."
                  log_cmd psql -p ${pgPort} -h localhost --no-password --username=supabase_admin -d postgres -c "CREATE EXTENSION IF NOT EXISTS orioledb;"
                fi

                log info "Loading prime SQL file"
                if ! log_cmd psql -p ${pgPort} -h localhost --no-password --username=supabase_admin -d postgres -v ON_ERROR_STOP=1 -Xf ${./tests/prime.sql} 2>&1; then
                  log error "Error executing SQL file"
                  exit 1
                fi

                # Create a table to store test configuration for pg_regress tests
                log info "Creating test_config table for pg_regress tests"
                log_cmd psql -p ${pgPort} -h localhost --no-password --username=supabase_admin -d postgres -c "
                  CREATE TABLE IF NOT EXISTS test_config (key TEXT PRIMARY KEY, value TEXT);
                  INSERT INTO test_config (key, value) VALUES ('http_mock_port', '$HTTP_MOCK_PORT')
                  ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
                "

                #shellcheck disable=SC2154
                mkdir -p "$out/regression_output"
                log info "Running pg_regress tests"
                if ! log_cmd pg_regress \
                  --use-existing \
                  --dbname=postgres \
                  --inputdir=${./tests} \
                  --outputdir="$out/regression_output" \
                  --host=localhost \
                  --port=${pgPort} \
                  --user=supabase_admin \
                  ${builtins.concatStringsSep " " sortedTestList} 2>&1; then
                  log error "pg_regress tests failed"
                  cat "$out/regression_output/regression.diffs"
                  exit 1
                fi
                log info "pg_regress tests completed successfully"

                log info "Running migrations tests"
                log_cmd pg_prove -p ${pgPort} -U supabase_admin -h localhost -d postgres -v ${../migrations/tests}/test.sql
                log info "Migrations tests completed successfully"
              '';
            };
        in
        {
          psql_15 = pkgs.runCommand "run-check-harness-psql-15" { } (
            lib.getExe (makeCheckHarness self'.packages."psql_15/bin")
          );
          psql_17 = pkgs.runCommand "run-check-harness-psql-17" { } (
            lib.getExe (makeCheckHarness self'.packages."psql_17/bin")
          );
          psql_orioledb-17 = pkgs.runCommand "run-check-harness-psql-orioledb-17" { } (
            lib.getExe (makeCheckHarness self'.packages."psql_orioledb-17/bin")
          );
          inherit (self'.packages)
            wal-g-2
            dbmate-tool
            packer
            pg_regress
            goss
            supascan
            ;
        }
        // pkgs.lib.optionalAttrs (pkgs.stdenv.isLinux) (
          {
            inherit (self'.packages)
              postgresql_15_debug
              postgresql_15_src
              postgresql_orioledb-17_debug
              postgresql_orioledb-17_src
              postgresql_17_debug
              postgresql_17_src
              ;
          }
          // (import ./ext/tests {
            inherit self;
            inherit pkgs;
          })
        )
        // pkgs.lib.optionalAttrs (system == "x86_64-linux") ({ devShell = self'.devShells.default; });
    };
}
