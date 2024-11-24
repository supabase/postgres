{
  description = "Prototype tooling for deploying PostgreSQL";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
    nix-editor.url = "github:snowfallorg/nix-editor";
  };

  outputs = { self, nixpkgs, flake-utils, nix2container, nix-editor, ...}:
    let
      gitRev = "vcs=${self.shortRev or "dirty"}+${builtins.substring 0 8 (self.lastModifiedDate or self.lastModified or "19700101")}";

      ourSystems = with flake-utils.lib; [
        system.x86_64-linux
        system.aarch64-linux
        system.aarch64-darwin
      ];
    in
    flake-utils.lib.eachSystem ourSystems (system:
      let
        pgsqlDefaultPort = "5435";
        pgsqlSuperuser = "supabase_admin";
        nix2img = nix2container.packages.${system}.nix2container;

        # The 'oriole_pkgs' variable holds all the upstream packages in nixpkgs, which
        # we can use to build our own images; it is the common name to refer to
        # a copy of nixpkgs which contains all its packages.
        # it also serves as a base for importing the orioldb/postgres overlay to
        #build the orioledb postgres patched version of postgresql16
        oriole_pkgs = import nixpkgs {
          config = { allowUnfree = true; };
          inherit system;
          overlays = [
            # NOTE (aseipp): add any needed overlays here. in theory we could
            # pull them from the overlays/ directory automatically, but we don't
            # want to have an arbitrary order, since it might matter. being
            # explicit is better.
            (import ./nix/overlays/cargo-pgrx.nix)
            (import ./nix/overlays/gdal-small.nix)
            (import ./nix/overlays/psql_16-oriole.nix)

          ];
        };
        #This variable works the same as 'oriole_pkgs' but builds using the upstream
        #nixpkgs builds of postgresql 15 and 16 + the overlays listed below
        pkgs = import nixpkgs {
          config = { 
            allowUnfree = true;
            permittedInsecurePackages = [
              "v8-9.7.106.18"
            ];  
          };
          inherit system;
          overlays = [
            # NOTE (aseipp): add any needed overlays here. in theory we could
            # pull them from the overlays/ directory automatically, but we don't
            # want to have an arbitrary order, since it might matter. being
            # explicit is better.
            (final: prev: {
              postgresql = final.callPackage ./nix/postgresql/default.nix {
                inherit (final) lib;
                inherit (final) stdenv;
                inherit (final) fetchurl;
                inherit (final) makeWrapper;
                inherit (final) callPackage;
              };
            })
            (import ./nix/overlays/cargo-pgrx-0-11-3.nix)
            # (import ./nix/overlays/postgis.nix)
            #(import ./nix/overlays/gdal-small.nix)

          ];
        };
        postgresql_15 = pkgs.postgresql.postgresql_15;
        postgresql = pkgs.postgresql.postgresql_15;
        sfcgal = pkgs.callPackage ./nix/ext/sfcgal/sfcgal.nix { };
        pg_regress = pkgs.callPackage ./nix/ext/pg_regress.nix { inherit postgresql; };
        supabase-groonga = pkgs.callPackage ./nix/supabase-groonga.nix { };
        mecab-naist-jdic = pkgs.callPackage ./nix/ext/mecab-naist-jdic/default.nix { };
        # Our list of PostgreSQL extensions which come from upstream Nixpkgs.
        # These are maintained upstream and can easily be used here just by
        # listing their name. Anytime the version of nixpkgs is upgraded, these
        # may also bring in new versions of the extensions.
        psqlExtensions = [
          /* pljava */
          /*"postgis"*/
        ];

        #FIXME for now, timescaledb is not included in the orioledb version of supabase extensions, as there is an issue
        # with building timescaledb with the orioledb patched version of postgresql
        orioledbPsqlExtensions = [
          /* pljava */
          /*"timescaledb"*/
        ];

        # Custom extensions that exist in our repository. These aren't upstream
        # either because nobody has done the work, maintaining them here is
        # easier and more expedient, or because they may not be suitable, or are
        # too niche/one-off.
        #
        # Ideally, most of these should have copies upstream for third party
        # use, but even if they did, keeping our own copies means that we can
        # rollout new versions of these critical things easier without having to
        # go through the upstream release engineering process.
        ourExtensions = [
          ./nix/ext/rum.nix
          ./nix/ext/timescaledb.nix
          ./nix/ext/timescaledb-2.9.1.nix
          ./nix/ext/pgroonga.nix
          ./nix/ext/index_advisor.nix
          ./nix/ext/wal2json.nix
          ./nix/ext/pgmq.nix
          ./nix/ext/pg_repack.nix
          ./nix/ext/pg-safeupdate.nix
          ./nix/ext/plpgsql-check.nix
          ./nix/ext/pgjwt.nix
          ./nix/ext/pgaudit.nix
          ./nix/ext/postgis.nix
          ./nix/ext/pgrouting.nix
          ./nix/ext/pgtap.nix
          ./nix/ext/pg_backtrace.nix
          ./nix/ext/pg_cron.nix
          ./nix/ext/pgsql-http.nix
          ./nix/ext/pg_plan_filter.nix
          ./nix/ext/pg_net.nix
          ./nix/ext/pg_hashids.nix
          ./nix/ext/pgsodium.nix
          ./nix/ext/pg_graphql.nix
          ./nix/ext/pg_stat_monitor.nix
          ./nix/ext/pg_jsonschema.nix
          ./nix/ext/pgvector.nix
          ./nix/ext/vault.nix
          ./nix/ext/hypopg.nix
          ./nix/ext/pg_tle.nix
          ./nix/ext/wrappers/default.nix
          ./nix/ext/supautils.nix
          ./nix/ext/plv8.nix
        ];

        #Where we import and build the orioledb extension, we add on our custom extensions
        # plus the orioledb option
        orioledbExtension = ourExtensions ++ [ ./nix/ext/orioledb.nix ];

        #this var is a convenience setting to import the orioledb patched version of postgresql
        postgresql_orioledb_16 = oriole_pkgs.postgresql_orioledb_16;
        #postgis_override = pkgs.postgis_override;
        getPostgresqlPackage = version:
          pkgs.postgresql."postgresql_${version}";
        #we will add supported versions to this list in the future
        supportedVersions = [ "15" ];
        # Create a 'receipt' file for a given postgresql package. This is a way
        # of adding a bit of metadata to the package, which can be used by other
        # tools to inspect what the contents of the install are: the PSQL
        # version, the installed extensions, et cetera.
        #
        # This takes three arguments:
        #  - pgbin: the postgresql package we are building on top of
        #  - upstreamExts: the list of extensions from upstream nixpkgs. This is
        #    not a list of packages, but an attrset containing extension names
        #    mapped to versions.
        #  - ourExts: the list of extensions from upstream nixpkgs. This is not
        #    a list of packages, but an attrset containing extension names
        #    mapped to versions.
        #
        # The output is a package containing the receipt.json file, which can be
        # merged with the PostgreSQL installation using 'symlinkJoin'.
        makeReceipt = pgbin: upstreamExts: ourExts: pkgs.writeTextFile {
          name = "receipt";
          destination = "/receipt.json";
          text = builtins.toJSON {
            revision = gitRev;
            psql-version = pgbin.version;
            nixpkgs = {
              revision = nixpkgs.rev;
              extensions = upstreamExts;
            };
            extensions = ourExts;

            # NOTE (aseipp): this field can be used to do cache busting (e.g.
            # force a rebuild of the psql packages) but also to helpfully inform
            # tools what version of the schema is being used, for forwards and
            # backwards compatibility
            receipt-version = "1";
          };
        };

        makeOurOrioleDbPostgresPkgs = version: patchedPostgres:
          let postgresql = patchedPostgres;
          in map (path: pkgs.callPackage path { inherit postgresql; }) orioledbExtension;

        makeOurPostgresPkgs = version:
          let postgresql = getPostgresqlPackage version;
          in map (path: pkgs.callPackage path { inherit postgresql; }) ourExtensions;

        # Create an attrset that contains all the extensions included in a server for the orioledb version of postgresql + extension.
        makeOurOrioleDbPostgresPkgsSet = version: patchedPostgres:
          (builtins.listToAttrs (map
            (drv:
              { name = drv.pname; value = drv; }
            )
            (makeOurOrioleDbPostgresPkgs version patchedPostgres)))
          // { recurseForDerivations = true; };

        # Create an attrset that contains all the extensions included in a server.
        makeOurPostgresPkgsSet = version:
          (builtins.listToAttrs (map
            (drv:
              { name = drv.pname; value = drv; }
            )
            (makeOurPostgresPkgs version)))
          // { recurseForDerivations = true; };


        # Create a binary distribution of PostgreSQL, given a version.
        #
        # NOTE: The version here does NOT refer to the exact PostgreSQL version;
        # it refers to the *major number only*, which is used to select the
        # correct version of the package from nixpkgs. This is because we want
        # to be able to do so in an open ended way. As an example, the version
        # "15" passed in will use the nixpkgs package "postgresql_15" as the
        # basis for building extensions, etc.
        makePostgresBin = version:
          let
            postgresql = getPostgresqlPackage version;
            upstreamExts = map
              (ext: {
                name = postgresql.pkgs."${ext}".pname;
                version = postgresql.pkgs."${ext}".version;
              })
              psqlExtensions;
            ourExts = map (ext: { name = ext.pname; version = ext.version; }) (makeOurPostgresPkgs version);

            pgbin = postgresql.withPackages (ps:
              (map (ext: ps."${ext}") psqlExtensions) ++ (makeOurPostgresPkgs version)
            );
          in
          pkgs.symlinkJoin {
            inherit (pgbin) name version;
            paths = [ pgbin (makeReceipt pgbin upstreamExts ourExts) ];
          };

        makeOrioleDbPostgresBin = version: patchedPostgres:
          let
            postgresql = patchedPostgres;
            upstreamExts = map
              (ext: {
                name = postgresql.pkgs."${ext}".pname;
                version = postgresql.pkgs."${ext}".version;
              })
              orioledbPsqlExtensions;
            ourExts = map (ext: { name = ext.pname; version = ext.version; }) (makeOurOrioleDbPostgresPkgs version postgresql);

            pgbin = postgresql.withPackages (ps:
              (map (ext: ps."${ext}") orioledbPsqlExtensions) ++ (makeOurOrioleDbPostgresPkgs version postgresql)
            );
          in
          pkgs.symlinkJoin {
            inherit (pgbin) name version;
            paths = [ pgbin (makeReceipt pgbin upstreamExts ourExts) ];
          };


        # Create an attribute set, containing all the relevant packages for a
        # PostgreSQL install, wrapped up with a bow on top. There are three
        # packages:
        #
        #  - bin: the postgresql package itself, with all the extensions
        #    installed, and a receipt.json file containing metadata about the
        #    install.
        #  - exts: an attrset containing all the extensions, mapped to their
        #    package names.
        makePostgres = version: rec {
          bin = makePostgresBin version;
          exts = makeOurPostgresPkgsSet version;
          recurseForDerivations = true;
        };
        makeOrioleDbPostgres = version: patchedPostgres: rec {
          bin = makeOrioleDbPostgresBin version patchedPostgres;
          exts = makeOurOrioleDbPostgresPkgsSet version patchedPostgres;
          recurseForDerivations = true;
        };

        # The base set of packages that we export from this Nix Flake, that can
        # be used with 'nix build'. Don't use the names listed below; check the
        # name in 'nix flake show' in order to make sure exactly what name you
        # want.
        basePackages = {
          supabase-groonga = supabase-groonga;
          # PostgreSQL versions.
          psql_15 = makePostgres "15";
          #psql_16 = makePostgres "16";
          #psql_orioledb_16 = makeOrioleDbPostgres "16_23" postgresql_orioledb_16;
          sfcgal = sfcgal;
          pg_regress = pg_regress;
          pg_prove = pkgs.perlPackages.TAPParserSourceHandlerpgTAP;
          postgresql_15 = pkgs.postgresql_15;

          postgresql_15_src = pkgs.stdenv.mkDerivation {
            pname = "postgresql-15-src";
            version = pkgs.postgresql_15.version;

            src = pkgs.postgresql_15.src;

            nativeBuildInputs = [ pkgs.bzip2 ];

            phases = [ "unpackPhase" "installPhase" ];

            installPhase = ''
              mkdir -p $out
              cp -r . $out
            '';

            meta = with pkgs.lib; {
              description = "PostgreSQL 15 source files";
              homepage = "https://www.postgresql.org/";
              license = licenses.postgresql;
              platforms = platforms.all;
            };
          };
          mecab_naist_jdic = mecab-naist-jdic;
          supabase_groonga = supabase-groonga;
          # Start a version of the server.
          start-server =
            let
              pgconfigFile = builtins.path {
                name = "postgresql.conf";
                path = ./ansible/files/postgresql_config/postgresql.conf.j2;
              };
              supautilsConfigFile = builtins.path {
                name = "supautils.conf";
                path = ./ansible/files/postgresql_config/supautils.conf.j2;
              };
              loggingConfigFile = builtins.path {
                name = "logging.conf";
                path = ./ansible/files/postgresql_config/postgresql-csvlog.conf;
              };
              readReplicaConfigFile = builtins.path {
                name = "readreplica.conf";
                path = ./ansible/files/postgresql_config/custom_read_replica.conf.j2;
              };
              pgHbaConfigFile = builtins.path {
                name = "pg_hba.conf";
                path = ./ansible/files/postgresql_config/pg_hba.conf.j2;
              };
              pgIdentConfigFile = builtins.path {
                name = "pg_ident.conf";
                path = ./ansible/files/postgresql_config/pg_ident.conf.j2;
              };
              postgresqlExtensionCustomScriptsPath = builtins.path {
                name = "extension-custom-scripts";
                path = ./ansible/files/postgresql_extension_custom_scripts;
              };
              getkeyScript = ./nix/tests/util/pgsodium_getkey.sh;
              localeArchive = if pkgs.stdenv.isDarwin
                then "${pkgs.darwin.locale}/share/locale"
                else "${pkgs.glibcLocales}/lib/locale/locale-archive";
            in
            pkgs.runCommand "start-postgres-server" { } ''
              mkdir -p $out/bin $out/etc/postgresql-custom $out/etc/postgresql $out/extension-custom-scripts
              cp ${supautilsConfigFile} $out/etc/postgresql-custom/supautils.conf || { echo "Failed to copy supautils.conf"; exit 1; }
              cp ${pgconfigFile} $out/etc/postgresql/postgresql.conf || { echo "Failed to copy postgresql.conf"; exit 1; }
              cp ${loggingConfigFile} $out/etc/postgresql-custom/logging.conf || { echo "Failed to copy logging.conf"; exit 1; }
              cp ${readReplicaConfigFile} $out/etc/postgresql-custom/read-replica.conf || { echo "Failed to copy read-replica.conf"; exit 1; }
              cp ${pgHbaConfigFile} $out/etc/postgresql/pg_hba.conf || { echo "Failed to copy pg_hba.conf"; exit 1; }
              cp ${pgIdentConfigFile} $out/etc/postgresql/pg_ident.conf || { echo "Failed to copy pg_ident.conf"; exit 1; }
              cp -r ${postgresqlExtensionCustomScriptsPath}/* $out/extension-custom-scripts/ || { echo "Failed to copy custom scripts"; exit 1; }
              echo "Copy operation completed"
              chmod 644 $out/etc/postgresql-custom/supautils.conf
              chmod 644 $out/etc/postgresql/postgresql.conf
              chmod 644 $out/etc/postgresql-custom/logging.conf
              chmod 644 $out/etc/postgresql/pg_hba.conf
              substitute ${./nix/tools/run-server.sh.in} $out/bin/start-postgres-server \
                --subst-var-by 'PGSQL_DEFAULT_PORT' '${pgsqlDefaultPort}' \
                --subst-var-by 'PGSQL_SUPERUSER' '${pgsqlSuperuser}' \
                --subst-var-by 'PSQL15_BINDIR' '${basePackages.psql_15.bin}' \
                --subst-var-by 'PSQL_CONF_FILE' $out/etc/postgresql/postgresql.conf \
                --subst-var-by 'PGSODIUM_GETKEY' '${getkeyScript}' \
                --subst-var-by 'READREPL_CONF_FILE' "$out/etc/postgresql-custom/read-replica.conf" \
                --subst-var-by 'LOGGING_CONF_FILE' "$out/etc/postgresql-custom/logging.conf" \
                --subst-var-by 'SUPAUTILS_CONF_FILE' "$out/etc/postgresql-custom/supautils.conf" \
                --subst-var-by 'PG_HBA' "$out/etc/postgresql/pg_hba.conf" \
                --subst-var-by 'PG_IDENT' "$out/etc/postgresql/pg_ident.conf" \
                --subst-var-by 'LOCALES' '${localeArchive}' \
                --subst-var-by 'EXTENSION_CUSTOM_SCRIPTS_DIR' "$out/extension-custom-scripts" \
                --subst-var-by 'MECAB_LIB' '${basePackages.psql_15.exts.pgroonga}/lib/groonga/plugins/tokenizers/tokenizer_mecab.so' \
                --subst-var-by 'GROONGA_DIR' '${supabase-groonga}' 

              chmod +x $out/bin/start-postgres-server
            '';

          # Start a version of the client and runs migrations script on server.
          start-client =
            let
              migrationsDir = ./migrations/db;
              postgresqlSchemaSql = ./nix/tools/postgresql_schema.sql;
              pgbouncerAuthSchemaSql = ./ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql;
              statExtensionSql = ./ansible/files/stat_extension.sql;
            in
            pkgs.runCommand "start-postgres-client" { } ''
              mkdir -p $out/bin
              substitute ${./nix/tools/run-client.sh.in} $out/bin/start-postgres-client \
                --subst-var-by 'PGSQL_DEFAULT_PORT' '${pgsqlDefaultPort}' \
                --subst-var-by 'PGSQL_SUPERUSER' '${pgsqlSuperuser}' \
                --subst-var-by 'PSQL15_BINDIR' '${basePackages.psql_15.bin}' \
                --subst-var-by 'MIGRATIONS_DIR' '${migrationsDir}' \
                --subst-var-by 'POSTGRESQL_SCHEMA_SQL' '${postgresqlSchemaSql}' \
                --subst-var-by 'PGBOUNCER_AUTH_SCHEMA_SQL' '${pgbouncerAuthSchemaSql}' \
                --subst-var-by 'STAT_EXTENSION_SQL' '${statExtensionSql}'
              chmod +x $out/bin/start-postgres-client
            '';

          # Migrate between two data directories.
          migrate-tool =
            let
              configFile = ./nix/tests/postgresql.conf.in;
              getkeyScript = ./nix/tests/util/pgsodium_getkey.sh;
              primingScript = ./nix/tests/prime.sql;
              migrationData = ./nix/tests/migrations/data.sql;
            in
            pkgs.runCommand "migrate-postgres" { } ''
              mkdir -p $out/bin
              substitute ${./nix/tools/migrate-tool.sh.in} $out/bin/migrate-postgres \
                --subst-var-by 'PSQL15_BINDIR' '${basePackages.psql_15.bin}' \
                --subst-var-by 'PSQL_CONF_FILE' '${configFile}' \
                --subst-var-by 'PGSODIUM_GETKEY' '${getkeyScript}' \
                --subst-var-by 'PRIMING_SCRIPT' '${primingScript}' \
                --subst-var-by 'MIGRATION_DATA' '${migrationData}'

              chmod +x $out/bin/migrate-postgres
            '';

          start-replica = pkgs.runCommand "start-postgres-replica" { } ''
            mkdir -p $out/bin
            substitute ${./nix/tools/run-replica.sh.in} $out/bin/start-postgres-replica \
              --subst-var-by 'PGSQL_SUPERUSER' '${pgsqlSuperuser}' \
              --subst-var-by 'PSQL15_BINDIR' '${basePackages.psql_15.bin}'
            chmod +x $out/bin/start-postgres-replica
          '';
          sync-exts-versions = pkgs.runCommand "sync-exts-versions" { } ''
            mkdir -p $out/bin
            substitute ${./nix/tools/sync-exts-versions.sh.in} $out/bin/sync-exts-versions \
              --subst-var-by 'YQ' '${pkgs.yq}/bin/yq' \
              --subst-var-by 'JQ' '${pkgs.jq}/bin/jq' \
              --subst-var-by 'NIX_EDITOR' '${nix-editor.packages.${system}.nix-editor}/bin/nix-editor' \
              --subst-var-by 'NIXPREFETCHURL' '${pkgs.nixVersions.nix_2_20}/bin/nix-prefetch-url' \
              --subst-var-by 'NIX' '${pkgs.nixVersions.nix_2_20}/bin/nix'
            chmod +x $out/bin/sync-exts-versions
          '';
        };

        # Create a testing harness for a PostgreSQL package. This is used for
        # 'nix flake check', and works with any PostgreSQL package you hand it.
        makeCheckHarness = pgpkg:
          let
            sqlTests = ./nix/tests/smoke;
            pg_prove = pkgs.perlPackages.TAPParserSourceHandlerpgTAP;
            supabase-groonga = pkgs.callPackage ./nix/supabase-groonga.nix { };
          in
          pkgs.runCommand "postgres-${pgpkg.version}-check-harness"
            {
              nativeBuildInputs = with pkgs; [ coreutils bash pgpkg pg_prove pg_regress procps supabase-groonga ];
            } ''
            TMPDIR=$(mktemp -d)
            if [ $? -ne 0 ]; then
              echo "Failed to create temp directory" >&2
              exit 1
            fi

            # Ensure the temporary directory is removed on exit
            trap 'rm -rf "$TMPDIR"' EXIT

            export PGDATA="$TMPDIR/pgdata"
            export PGSODIUM_DIR="$TMPDIR/pgsodium"

            mkdir -p $PGDATA
            mkdir -p $TMPDIR/logfile
            # Generate a random key and store it in an environment variable
            export PGSODIUM_KEY=$(head -c 32 /dev/urandom | od -A n -t x1 | tr -d ' \n')
            export GRN_PLUGINS_DIR=${supabase-groonga}/lib/groonga/plugins
            # Create a simple script to echo the key
            echo '#!/bin/sh' > $TMPDIR/getkey.sh
            echo 'echo $PGSODIUM_KEY' >> $TMPDIR/getkey.sh
            chmod +x $TMPDIR/getkey.sh
            initdb --locale=C --username=supabase_admin
            substitute ${./nix/tests/postgresql.conf.in} $PGDATA/postgresql.conf \
              --subst-var-by PGSODIUM_GETKEY_SCRIPT "$TMPDIR/getkey.sh"
            echo "listen_addresses = '*'" >> $PGDATA/postgresql.conf
            echo "port = 5432" >> $PGDATA/postgresql.conf
            echo "host all all 127.0.0.1/32 trust" >> $PGDATA/pg_hba.conf
            #postgres -D "$PGDATA" -k "$TMPDIR" -h localhost -p 5432 >$TMPDIR/logfile/postgresql.log 2>&1 &
            pg_ctl -D "$PGDATA" -l $TMPDIR/logfile/postgresql.log -o "-k $TMPDIR -p 5432" start
            for i in {1..60}; do
              if pg_isready -h localhost -p 5432; then
                echo "PostgreSQL is ready"
                break
              fi
              sleep 1
              if [ $i -eq 60 ]; then
                echo "PostgreSQL is not ready after 60 seconds"
                echo "PostgreSQL status:"
                pg_ctl -D "$PGDATA" status
                echo "PostgreSQL log content:"
                cat $TMPDIR/logfile/postgresql.log
                exit 1
              fi
            done
            createdb -p 5432 -h localhost --username=supabase_admin testing
            if ! psql -p 5432 -h localhost --username=supabase_admin -d testing -v ON_ERROR_STOP=1 -Xaf ${./nix/tests/prime.sql}; then
              echo "Error executing SQL file. PostgreSQL log content:"
              cat $TMPDIR/logfile/postgresql.log
              pg_ctl -D "$PGDATA" stop
              exit 1
            fi
            pg_prove -p 5432 -h localhost --username=supabase_admin -d testing ${sqlTests}/*.sql

            mkdir -p $out/regression_output
            pg_regress \
              --use-existing \
              --dbname=testing \
              --inputdir=${./nix/tests} \
              --outputdir=$out/regression_output \
              --host=localhost \
              --port=5432 \
              --user=supabase_admin \
              $(ls ${./nix/tests/sql} | sed -e 's/\..*$//' | sort )

            pg_ctl -D "$PGDATA" stop
            mv $TMPDIR/logfile/postgresql.log $out
            echo ${pgpkg}
          '';
      in
      rec {
        # The list of all packages that can be built with 'nix build'. The list
        # of names that can be used can be shown with 'nix flake show'
        packages = flake-utils.lib.flattenTree basePackages // {
          # Any extra packages we might want to include in our package
          # set can go here.
          inherit (pkgs)
            # NOTE: comes from our cargo-pgrx-0-11-3.nix overlay
            cargo-pgrx_0_11_3;

        };

        # The list of exported 'checks' that are run with every run of 'nix
        # flake check'. This is run in the CI system, as well.
        checks = {
          psql_15 = makeCheckHarness basePackages.psql_15.bin;
          #psql_16 = makeCheckHarness basePackages.psql_16.bin;
          #psql_orioledb_16 = makeCheckHarness basePackages.psql_orioledb_16.bin;
        };

        # Apps is a list of names of things that can be executed with 'nix run';
        # these are distinct from the things that can be built with 'nix build',
        # so they need to be listed here too.
        apps =
          let
            mkApp = attrName: binName: {
              type = "app";
              program = "${basePackages."${attrName}"}/bin/${binName}";
            };
          in
          {
            start-server = mkApp "start-server" "start-postgres-server";
            start-client = mkApp "start-client" "start-postgres-client";
            start-replica = mkApp "start-replica" "start-postgres-replica";
            migration-test = mkApp "migrate-tool" "migrate-postgres";
            sync-exts-versions = mkApp "sync-exts-versions" "sync-exts-versions";
          };

        # 'devShells.default' lists the set of packages that are included in the
        # ambient $PATH environment when you run 'nix develop'. This is useful
        # for development and puts many convenient devtools instantly within
        # reach.
        devShells.default = pkgs.mkShell {
          packages = with pkgs; [
            coreutils
            just
            nix-update
            #pg_prove
            shellcheck
            ansible
            ansible-lint
            (packer.overrideAttrs (oldAttrs: {
              version = "1.7.8";
            }))

            basePackages.start-server
            basePackages.start-client
            basePackages.start-replica
            basePackages.migrate-tool
            basePackages.sync-exts-versions
          ];
          shellHook = ''
            export HISTFILE=.history
          '';
        };
      }
    );
}
