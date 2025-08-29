{ self, ... }:
{
  perSystem =
    {
      lib,
      self',
      system,
      pkgs,
      ...
    }:
    let
      pkgs-lib = pkgs.callPackage ./packages/lib.nix {
        psql_15 = self'.packages."psql_15/bin";
        psql_17 = self'.packages."psql_17/bin";
        psql_orioledb-17 = self'.packages."psql_orioledb-17/bin";
        pgroonga = self'.packages."psql_15/exts/pgroonga";
        inherit (self.supabase) defaults;
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
              pg_regress = self'.packages.pg_regress;
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

              # Use the shared setup but with a test-specific name
              start-postgres-server-bin = pkgs-lib.makePostgresDevSetup {
                inherit pkgs;
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
                if builtins.match "15.*" name != null then
                  "15"
                else if builtins.match "17.*" name != null then
                  "17"
                else if builtins.match "orioledb-17.*" name != null then
                  "orioledb-17"
                else
                  throw "Unsupported PostgreSQL version: ${name}";

              # Helper function to filter SQL files based on version
              filterTestFiles =
                version: dir:
                let
                  files = builtins.readDir dir;
                  isValidFile =
                    name:
                    let
                      isVersionSpecific = builtins.match "z_.*" name != null;
                      matchesVersion =
                        if isVersionSpecific then
                          if version == "orioledb-17" then
                            builtins.match "z_orioledb-17_.*" name != null
                          else if version == "17" then
                            builtins.match "z_17_.*" name != null
                          else
                            builtins.match "z_15_.*" name != null
                        else
                          true;
                    in
                    pkgs.lib.hasSuffix ".sql" name && matchesVersion;
                in
                pkgs.lib.filterAttrs (name: _: isValidFile name) files;

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
                builtins.trace "Major version result: ${result}" result; # Trace the result                                             # For "15.8"

              # Filter SQL test files
              filteredSqlTests = filterTestFiles majorVersion ./tests/sql;

              pgPort =
                if (majorVersion == "17") then
                  "5535"
                else if (majorVersion == "15") then
                  "5536"
                else
                  "5537";

              # Convert filtered tests to a sorted list of basenames (without extension)
              testList = pkgs.lib.mapAttrsToList (
                name: _: builtins.substring 0 (pkgs.lib.stringLength name - 4) name
              ) filteredSqlTests;
              sortedTestList = builtins.sort (a: b: a < b) testList;
            in
            pkgs.runCommand "postgres-${pgpkg.version}-check-harness"
              {
                nativeBuildInputs = with pkgs; [
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
                ];
              }
              ''
                set -e

                #First we need to create a generic pg cluster for pgtap tests and run those
                export GRN_PLUGINS_DIR=${pkgs.supabase-groonga}/lib/groonga/plugins
                PGTAP_CLUSTER=$(mktemp -d)
                initdb --locale=C --username=supabase_admin -D "$PGTAP_CLUSTER"
                substitute ${./tests/postgresql.conf.in} "$PGTAP_CLUSTER"/postgresql.conf \
                  --subst-var-by PGSODIUM_GETKEY_SCRIPT "${getkey-script}/bin/pgsodium-getkey"
                echo "listen_addresses = '*'" >> "$PGTAP_CLUSTER"/postgresql.conf
                echo "port = ${pgPort}" >> "$PGTAP_CLUSTER"/postgresql.conf
                echo "host all all 127.0.0.1/32 trust" >> $PGTAP_CLUSTER/pg_hba.conf
                echo "Checking shared_preload_libraries setting:"
                grep -rn "shared_preload_libraries" "$PGTAP_CLUSTER"/postgresql.conf
                # Remove timescaledb if running orioledb-17 check
                echo "I AM ${pgpkg.version}===================================================="
                if [[ "${pgpkg.version}" == *"17"* ]]; then
                  perl -pi -e 's/ timescaledb,//g' "$PGTAP_CLUSTER/postgresql.conf"
                fi
                #NOTE in the future we may also need to add the orioledb extension to the cluster when cluster is oriole
                echo "PGTAP_CLUSTER directory contents:"
                ls -la "$PGTAP_CLUSTER"

                # Check if postgresql.conf exists
                if [ ! -f "$PGTAP_CLUSTER/postgresql.conf" ]; then
                    echo "postgresql.conf is missing!"
                    exit 1
                fi

                # PostgreSQL startup
                if [[ "$(uname)" == "Darwin" ]]; then
                pg_ctl -D "$PGTAP_CLUSTER" -l "$PGTAP_CLUSTER"/postgresql.log -o "-k "$PGTAP_CLUSTER" -p ${pgPort} -d 5" start 2>&1
                else
                mkdir -p "$PGTAP_CLUSTER/sockets"
                pg_ctl -D "$PGTAP_CLUSTER" -l "$PGTAP_CLUSTER"/postgresql.log -o "-k $PGTAP_CLUSTER/sockets -p ${pgPort} -d 5" start 2>&1
                fi || {
                echo "pg_ctl failed to start PostgreSQL"
                echo "Contents of postgresql.log:"
                cat "$PGTAP_CLUSTER"/postgresql.log
                exit 1
                }
                for i in {1..60}; do
                  if pg_isready -h ${self.supabase.defaults.host} -p ${pgPort}; then
                    echo "PostgreSQL is ready"
                    break
                  fi
                  sleep 1
                  if [ $i -eq 60 ]; then
                    echo "PostgreSQL is not ready after 60 seconds"
                    echo "PostgreSQL status:"
                    pg_ctl -D "$PGTAP_CLUSTER" status
                    echo "PostgreSQL log content:"
                    cat "$PGTAP_CLUSTER"/postgresql.log
                    exit 1
                  fi
                done
                createdb -p ${pgPort} -h ${self.supabase.defaults.host} --username=supabase_admin testing
                if ! psql -p ${pgPort} -h ${self.supabase.defaults.host} --username=supabase_admin -d testing -v ON_ERROR_STOP=1 -Xf ${./tests/prime.sql}; then
                  echo "Error executing SQL file. PostgreSQL log content:"
                  cat "$PGTAP_CLUSTER"/postgresql.log
                  pg_ctl -D "$PGTAP_CLUSTER" stop
                  exit 1
                fi
                SORTED_DIR=$(mktemp -d)
                for t in $(printf "%s\n" ${builtins.concatStringsSep " " sortedTestList}); do
                  psql -p ${pgPort} -h ${self.supabase.defaults.host} --username=supabase_admin -d testing -f "${./tests/sql}/$t.sql" || true
                done
                rm -rf "$SORTED_DIR"
                pg_ctl -D "$PGTAP_CLUSTER" stop
                rm -rf $PGTAP_CLUSTER

                # End of pgtap tests
                # from here on out we are running pg_regress tests, we use a different cluster for this
                # which is start by the start-postgres-server-bin script
                # start-postgres-server-bin script closely matches our AMI setup, configurations and migrations

                unset GRN_PLUGINS_DIR
                ${start-postgres-server-bin}/bin/start-postgres-server ${getVersionArg pgpkg} --daemonize

                for i in {1..60}; do
                    if pg_isready -h ${self.supabase.defaults.host} -p ${pgPort} -U supabase_admin -q; then
                        echo "PostgreSQL is ready"
                        break
                    fi
                    sleep 1
                    if [ $i -eq 60 ]; then
                        echo "PostgreSQL failed to start"
                        exit 1
                    fi
                done

                if ! psql -p ${pgPort} -h ${self.supabase.defaults.host} --no-password --username=supabase_admin -d postgres -v ON_ERROR_STOP=1 -Xf ${./tests/prime.sql}; then
                  echo "Error executing SQL file"
                  exit 1
                fi

                mkdir -p $out/regression_output
                if ! pg_regress \
                  --use-existing \
                  --dbname=postgres \
                  --inputdir=${./tests} \
                  --outputdir=$out/regression_output \
                  --host=${self.supabase.defaults.host} \
                  --port=${pgPort} \
                  --user=supabase_admin \
                  ${builtins.concatStringsSep " " sortedTestList}; then
                  echo "pg_regress tests failed"
                  cat $out/regression_output/regression.diffs
                  exit 1
                fi

                echo "Running migrations tests"
                pg_prove -p ${pgPort} -U supabase_admin -h ${self.supabase.defaults.host} -d postgres -v ${../migrations/tests}/test.sql

                # Copy logs to output
                for logfile in $(find /tmp -name postgresql.log -type f); do
                  cp "$logfile" $out/postgresql.log
                done
                exit 0
              '';
        in
        {
          psql_15 = makeCheckHarness self'.packages."psql_15/bin";
          psql_17 = makeCheckHarness self'.packages."psql_17/bin";
          psql_orioledb-17 = makeCheckHarness self'.packages."psql_orioledb-17/bin";
          inherit (self'.packages)
            wal-g-2
            wal-g-3
            dbmate-tool
            packer
            pg_regress
            ;
        }
        // pkgs.lib.optionalAttrs (system == "aarch64-linux") {
          inherit (self'.packages)
            postgresql_15_debug
            postgresql_15_src
            postgresql_orioledb-17_debug
            postgresql_orioledb-17_src
            postgresql_17_debug
            postgresql_17_src
            ;
        }
        // pkgs.lib.optionalAttrs (system == "x86_64-linux") (
          {
            devShell = self'.devShells.default;
          }
          // (import ./ext/tests {
            inherit self;
            inherit pkgs;
          })
        );
    };
}
