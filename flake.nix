{
  description = "Prototype tooling for deploying PostgreSQL";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixpkgs-unstable";
    flake-utils.url = "github:numtide/flake-utils";
    nix2container.url = "github:nlewo/nix2container";
    nix-editor.url = "github:snowfallorg/nix-editor";
    rust-overlay.url = "github:oxalica/rust-overlay";
  };

  outputs = { self, nixpkgs, flake-utils, nix-editor, rust-overlay, nix2container, ... }:
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
        pgsqlDefaultHost = "localhost";
        pgsqlSuperuser = "supabase_admin";

        pkgs = import nixpkgs {
          config = {
            allowUnfree = true;
            permittedInsecurePackages = [
              "v8-9.7.106.18"
            ];
          };
          inherit system;
          overlays = [
            # NOTE: add any needed overlays here. in theory we could
            # pull them from the overlays/ directory automatically, but we don't
            # want to have an arbitrary order, since it might matter. being
            # explicit is better.
            (final: prev: {
              xmrig = throw "The xmrig package has been explicitly disabled in this flake.";
            })
            (import rust-overlay)
            (final: prev: {
              cargo-pgrx = final.callPackage ./nix/cargo-pgrx/default.nix {
                inherit (final) lib;
                inherit (final) darwin;
                inherit (final) fetchCrate;
                inherit (final) openssl;
                inherit (final) pkg-config;
                inherit (final) makeRustPlatform;
                inherit (final) stdenv;
                inherit (final) rust-bin;
              };

              buildPgrxExtension = final.callPackage ./nix/cargo-pgrx/buildPgrxExtension.nix {
                inherit (final) cargo-pgrx;
                inherit (final) lib;
                inherit (final) Security;
                inherit (final) pkg-config;
                inherit (final) makeRustPlatform;
                inherit (final) stdenv;
                inherit (final) writeShellScriptBin;
              };

              buildPgrxExtension_0_11_3 = prev.buildPgrxExtension.override {
                cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_11_3;
              };

              buildPgrxExtension_0_12_6 = prev.buildPgrxExtension.override {
                cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_12_6;
              };

              buildPgrxExtension_0_12_9 = prev.buildPgrxExtension.override {
                cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_12_9;
              };

              buildPgrxExtension_0_14_3 = prev.buildPgrxExtension.override {
                cargo-pgrx = final.cargo-pgrx.cargo-pgrx_0_14_3;
              };

            })
            (final: prev: {
              postgresql = final.callPackage ./nix/postgresql/default.nix {
                inherit (final) lib stdenv fetchurl makeWrapper callPackage buildEnv newScope;
              };
            })
          ];
        };
        # Define pythonEnv here
        pythonEnv = pkgs.python3.withPackages (ps: with ps; [
          boto3
          docker
          pytest
          pytest-testinfra
          requests
          ec2instanceconnectcli
          paramiko
        ]);
        sfcgal = pkgs.callPackage ./nix/ext/sfcgal/sfcgal.nix { };
        supabase-groonga = pkgs.callPackage ./nix/supabase-groonga.nix { };
        mecab-naist-jdic = pkgs.callPackage ./nix/ext/mecab-naist-jdic/default.nix { };
        inherit (pkgs.callPackage ./nix/wal-g.nix { }) wal-g-2 wal-g-3;
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
        #we're not using timescaledb or plv8 in the orioledb-17 version or pg 17 of supabase extensions
        orioleFilteredExtensions = builtins.filter
          (
            x:
            x != ./nix/ext/timescaledb.nix &&
            x != ./nix/ext/timescaledb-2.9.1.nix &&
            x != ./nix/ext/plv8.nix
        ) ourExtensions;

        orioledbExtensions = orioleFilteredExtensions ++ [ ./nix/ext/orioledb.nix ];
        dbExtensions17 = orioleFilteredExtensions;
        getPostgresqlPackage = version:
          pkgs.postgresql."postgresql_${version}";
        # Create a 'receipt' file for a given postgresql package. This is a way
        # of adding a bit of metadata to the package, which can be used by other
        # tools to inspect what the contents of the install are: the PSQL
        # version, the installed extensions, et cetera.
        #
        # This takes two arguments:
        #  - pgbin: the postgresql package we are building on top of
        #    not a list of packages, but an attrset containing extension names
        #    mapped to versions.
        #  - ourExts: the list of extensions from upstream nixpkgs. This is not
        #    a list of packages, but an attrset containing extension names
        #    mapped to versions.
        #
        # The output is a package containing the receipt.json file, which can be
        # merged with the PostgreSQL installation using 'symlinkJoin'.
        makeReceipt = pgbin: ourExts: pkgs.writeTextFile {
          name = "receipt";
          destination = "/receipt.json";
          text = builtins.toJSON {
            revision = gitRev;
            psql-version = pgbin.version;
            nixpkgs = {
              revision = nixpkgs.rev;
            };
            extensions = ourExts;

            # NOTE this field can be used to do cache busting (e.g.
            # force a rebuild of the psql packages) but also to helpfully inform
            # tools what version of the schema is being used, for forwards and
            # backwards compatibility
            receipt-version = "1";
          };
        };

        makeOurPostgresPkgs = version:
          let
            postgresql = getPostgresqlPackage version;
            extensionsToUse =
              if (builtins.elem version [ "orioledb-17" ])
              then orioledbExtensions
              else if (builtins.elem version [ "17" ])
              then dbExtensions17
              else ourExtensions;
          in
          map (path: pkgs.callPackage path { inherit postgresql; }) extensionsToUse;

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
            ourExts = map (ext: { name = ext.pname; version = ext.version; }) (makeOurPostgresPkgs version);

            pgbin = postgresql.withPackages (ps:
              makeOurPostgresPkgs version
            );
          in
          pkgs.symlinkJoin {
            inherit (pgbin) name version;
            paths = [ pgbin (makeReceipt pgbin ourExts) ];
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

        makePostgresDevSetup = { pkgs, name, extraSubstitutions ? { } }:
          let
            paths = {
              migrationsDir = builtins.path {
                name = "migrations";
                path = ./migrations/db;
              };
              postgresqlSchemaSql = builtins.path {
                name = "postgresql-schema";
                path = ./nix/tools/postgresql_schema.sql;
              };
              pgbouncerAuthSchemaSql = builtins.path {
                name = "pgbouncer-auth-schema";
                path = ./ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql;
              };
              statExtensionSql = builtins.path {
                name = "stat-extension";
                path = ./ansible/files/stat_extension.sql;
              };
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
              getkeyScript = builtins.path {
                name = "pgsodium_getkey.sh";
                path = ./nix/tests/util/pgsodium_getkey.sh;
              };
            };

            localeArchive =
              if pkgs.stdenv.isDarwin
              then "${pkgs.darwin.locale}/share/locale"
              else "${pkgs.glibcLocales}/lib/locale/locale-archive";

            substitutions = {
              SHELL_PATH = "${pkgs.bash}/bin/bash";
              PGSQL_DEFAULT_PORT = "${pgsqlDefaultPort}";
              PGSQL_SUPERUSER = "${pgsqlSuperuser}";
              PSQL15_BINDIR = "${basePackages.psql_15.bin}";
              PSQL17_BINDIR = "${basePackages.psql_17.bin}";
              PSQL_CONF_FILE = "${paths.pgconfigFile}";
              PSQLORIOLEDB17_BINDIR = "${basePackages.psql_orioledb-17.bin}";
              PGSODIUM_GETKEY = "${paths.getkeyScript}";
              READREPL_CONF_FILE = "${paths.readReplicaConfigFile}";
              LOGGING_CONF_FILE = "${paths.loggingConfigFile}";
              SUPAUTILS_CONF_FILE = "${paths.supautilsConfigFile}";
              PG_HBA = "${paths.pgHbaConfigFile}";
              PG_IDENT = "${paths.pgIdentConfigFile}";
              LOCALES = "${localeArchive}";
              EXTENSION_CUSTOM_SCRIPTS_DIR = "${paths.postgresqlExtensionCustomScriptsPath}";
              MECAB_LIB = "${basePackages.psql_15.exts.pgroonga}/lib/groonga/plugins/tokenizers/tokenizer_mecab.so";
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
              inherit (paths) migrationsDir postgresqlSchemaSql pgbouncerAuthSchemaSql statExtensionSql;
            } ''
            mkdir -p $out/bin $out/etc/postgresql-custom $out/etc/postgresql $out/extension-custom-scripts

            # Copy config files with error handling
            cp ${paths.supautilsConfigFile} $out/etc/postgresql-custom/supautils.conf || { echo "Failed to copy supautils.conf"; exit 1; }
            cp ${paths.pgconfigFile} $out/etc/postgresql/postgresql.conf || { echo "Failed to copy postgresql.conf"; exit 1; }
            cp ${paths.loggingConfigFile} $out/etc/postgresql-custom/logging.conf || { echo "Failed to copy logging.conf"; exit 1; }
            cp ${paths.readReplicaConfigFile} $out/etc/postgresql-custom/read-replica.conf || { echo "Failed to copy read-replica.conf"; exit 1; }
            cp ${paths.pgHbaConfigFile} $out/etc/postgresql/pg_hba.conf || { echo "Failed to copy pg_hba.conf"; exit 1; }
            cp ${paths.pgIdentConfigFile} $out/etc/postgresql/pg_ident.conf || { echo "Failed to copy pg_ident.conf"; exit 1; }
            cp -r ${paths.postgresqlExtensionCustomScriptsPath}/* $out/extension-custom-scripts/ || { echo "Failed to copy custom scripts"; exit 1; }

            echo "Copy operation completed"
            chmod 644 $out/etc/postgresql-custom/supautils.conf
            chmod 644 $out/etc/postgresql/postgresql.conf
            chmod 644 $out/etc/postgresql-custom/logging.conf
            chmod 644 $out/etc/postgresql/pg_hba.conf

            substitute ${./nix/tools/run-server.sh.in} $out/bin/start-postgres-server \
              ${builtins.concatStringsSep " " (builtins.attrValues (builtins.mapAttrs
                (name: value: "--subst-var-by '${name}' '${value}'")
                substitutions
              ))}
            chmod +x $out/bin/start-postgres-server
          '';

        # The base set of packages that we export from this Nix Flake, that can
        # be used with 'nix build'. Don't use the names listed below; check the
        # name in 'nix flake show' in order to make sure exactly what name you
        # want.
        basePackages =
          let
            # Function to get the PostgreSQL version from the attribute name
            getVersion = name:
              let
                match = builtins.match "psql_([0-9]+)" name;
              in
              if match == null then null else builtins.head match;

            # Define the available PostgreSQL versions
            postgresVersions = {
              psql_15 = makePostgres "15";
              psql_17 = makePostgres "17";
              psql_orioledb-17 = makePostgres "orioledb-17";
            };

            # Find the active PostgreSQL version
            activeVersion = getVersion (builtins.head (builtins.attrNames postgresVersions));

            # Function to create the pg_regress package
            makePgRegress = version:
              let
                postgresqlPackage = pkgs."postgresql_${version}";
              in
              pkgs.callPackage ./nix/ext/pg_regress.nix {
                postgresql = postgresqlPackage;
              };
            postgresql_15 = getPostgresqlPackage "15";
            postgresql_17 = getPostgresqlPackage "17";
            postgresql_orioledb-17 = getPostgresqlPackage "orioledb-17";
          in
          postgresVersions // {
            supabase-groonga = supabase-groonga;
            cargo-pgrx_0_11_3 = pkgs.cargo-pgrx.cargo-pgrx_0_11_3;
            cargo-pgrx_0_12_6 = pkgs.cargo-pgrx.cargo-pgrx_0_12_6;
            cargo-pgrx_0_12_9 = pkgs.cargo-pgrx.cargo-pgrx_0_12_9;
            cargo-pgrx_0_14_3 = pkgs.cargo-pgrx.cargo-pgrx_0_14_3;
            # PostgreSQL versions.
            psql_15 = postgresVersions.psql_15;
            psql_17 = postgresVersions.psql_17;
            psql_orioledb-17 = postgresVersions.psql_orioledb-17;
            wal-g-2 = wal-g-2;
            wal-g-3 = wal-g-3;
            sfcgal = sfcgal;
            pg_prove = pkgs.perlPackages.TAPParserSourceHandlerpgTAP;
            inherit postgresql_15 postgresql_17 postgresql_orioledb-17;
            postgresql_15_debug = if pkgs.stdenv.isLinux then postgresql_15.debug else null;
            postgresql_17_debug = if pkgs.stdenv.isLinux then postgresql_17.debug else null;
            postgresql_orioledb-17_debug = if pkgs.stdenv.isLinux then postgresql_orioledb-17.debug else null;
            postgresql_15_src = pkgs.stdenv.mkDerivation {
              pname = "postgresql-15-src";
              version = postgresql_15.version;

              src = postgresql_15.src;

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
            postgresql_17_src = pkgs.stdenv.mkDerivation {
              pname = "postgresql-17-src";
              version = postgresql_17.version;
              src = postgresql_17.src;

              nativeBuildInputs = [ pkgs.bzip2 ];

              phases = [ "unpackPhase" "installPhase" ];

              installPhase = ''
                mkdir -p $out
                cp -r . $out
              '';
              meta = with pkgs.lib; {
                description = "PostgreSQL 17 source files";
                homepage = "https://www.postgresql.org/";
                license = licenses.postgresql;
                platforms = platforms.all;
              };
            };
            postgresql_orioledb-17_src = pkgs.stdenv.mkDerivation {
              pname = "postgresql-17-src";
              version = postgresql_orioledb-17.version;

              src = postgresql_orioledb-17.src;

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
            pg_regress = makePgRegress activeVersion;
            # Start a version of the server.
            start-server = makePostgresDevSetup {
              inherit pkgs;
              name = "start-postgres-server";
            };

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
                  --subst-var-by 'PSQL17_BINDIR' '${basePackages.psql_17.bin}' \
                  --subst-var-by 'PSQLORIOLEDB17_BINDIR' '${basePackages.psql_orioledb-17.bin}' \
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
            pg-restore =
              pkgs.runCommand "run-pg-restore" { } ''
                mkdir -p $out/bin
                substitute ${./nix/tools/run-restore.sh.in} $out/bin/pg-restore \
                  --subst-var-by PSQL15_BINDIR '${basePackages.psql_15.bin}'
                chmod +x $out/bin/pg-restore
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

            local-infra-bootstrap = pkgs.runCommand "local-infra-bootstrap" { } ''
              mkdir -p $out/bin
              substitute ${./nix/tools/local-infra-bootstrap.sh.in} $out/bin/local-infra-bootstrap
              chmod +x $out/bin/local-infra-bootstrap
            '';
            dbmate-tool =
              let
                migrationsDir = ./migrations/db;
                ansibleVars = ./ansible/vars.yml;
                pgbouncerAuthSchemaSql = ./ansible/files/pgbouncer_config/pgbouncer_auth_schema.sql;
                statExtensionSql = ./ansible/files/stat_extension.sql;
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
                } ''
                mkdir -p $out/bin $out/migrations
                cp -r ${migrationsDir}/* $out
                substitute ${./nix/tools/dbmate-tool.sh.in} $out/bin/dbmate-tool \
                  --subst-var-by 'PGSQL_DEFAULT_PORT' '${pgsqlDefaultPort}' \
                  --subst-var-by 'MIGRATIONS_DIR' $out \
                  --subst-var-by 'PGSQL_SUPERUSER' '${pgsqlSuperuser}' \
                  --subst-var-by 'ANSIBLE_VARS' ${ansibleVars} \
                  --subst-var-by 'CURRENT_SYSTEM' '${system}' \
                  --subst-var-by 'PGBOUNCER_AUTH_SCHEMA_SQL' '${pgbouncerAuthSchemaSql}' \
                  --subst-var-by 'STAT_EXTENSION_SQL' '${statExtensionSql}'
                chmod +x $out/bin/dbmate-tool
                wrapProgram $out/bin/dbmate-tool \
                  --prefix PATH : ${pkgs.lib.makeBinPath [ pkgs.overmind pkgs.dbmate pkgs.nix pkgs.jq pkgs.yq ]}
              '';
            show-commands = pkgs.runCommand "show-commands"
              {
                nativeBuildInputs = [ pkgs.makeWrapper ];
                buildInputs = [ pkgs.nushell ];
              } ''
              mkdir -p $out/bin
              cat > $out/bin/show-commands << 'EOF'
              #!${pkgs.nushell}/bin/nu
              let json_output = (nix flake show --json --quiet --all-systems | from json)
              let apps = ($json_output | get apps.${system})
              $apps | transpose name info | select name | each { |it| echo $"Run this app with: nix run .#($it.name)" }
              EOF
              chmod +x $out/bin/show-commands
              wrapProgram $out/bin/show-commands \
                --prefix PATH : ${pkgs.nushell}/bin
            '';
            update-readme = pkgs.runCommand "update-readme"
              {
                nativeBuildInputs = [ pkgs.makeWrapper ];
                buildInputs = [ pkgs.nushell ];
              } ''
              mkdir -p $out/bin
              cp ${./nix/tools/update_readme.nu} $out/bin/update-readme
              chmod +x $out/bin/update-readme
              wrapProgram $out/bin/update-readme \
                --prefix PATH : ${pkgs.nushell}/bin
            '';
            # Script to run the AMI build and tests locally
            build-test-ami = pkgs.runCommand "build-test-ami"
              {
                buildInputs = with pkgs; [
                  packer
                  awscli2
                  yq
                  jq
                  openssl
                  git
                  coreutils
                  aws-vault
                ];
              } ''
                mkdir -p $out/bin
                cat > $out/bin/build-test-ami << 'EOL'
                #!/usr/bin/env bash
                set -euo pipefail

                show_help() {
                  cat << EOF
                Usage: build-test-ami [--help] <postgres-version>

                Build AMI images for PostgreSQL testing.

                This script will:
                1. Check for required tools and AWS authentication
                2. Build two AMI stages using Packer
                3. Clean up any temporary instances
                4. Output the final AMI name for use with run-testinfra

                Arguments:
                  postgres-version    PostgreSQL major version to build (required)

                Options:
                  --help    Show this help message and exit

                Requirements:
                  - AWS Vault profile must be set in AWS_VAULT environment variable
                  - Packer, AWS CLI, yq, jq, and OpenSSL must be installed
                  - Must be run from a git repository

                Example:
                  aws-vault exec <profile-name> -- nix run .#build-test-ami 15
                EOF
                }

                # Handle help flag
                if [[ "$#" -gt 0 && "$1" == "--help" ]]; then
                  show_help
                  exit 0
                fi

                export PATH="${pkgs.lib.makeBinPath (with pkgs; [
                  packer
                  awscli2
                  yq
                  jq
                  openssl
                  git
                  coreutils
                  aws-vault
                ])}:$PATH"

                # Check for required tools
                for cmd in packer aws-vault yq jq openssl; do
                  if ! command -v $cmd &> /dev/null; then
                    echo "Error: $cmd is required but not found"
                    exit 1
                  fi
                done

                # Check AWS Vault profile
                if [ -z "''${AWS_VAULT:-}" ]; then
                  echo "Error: AWS_VAULT environment variable must be set with the profile name"
                  echo "Usage: aws-vault exec <profile-name> -- nix run .#build-test-ami <postgres-version>"
                  exit 1
                fi

                # Set values
                REGION="ap-southeast-1"
                POSTGRES_VERSION="$1"
                RANDOM_STRING=$(openssl rand -hex 8)
                GIT_SHA=$(git rev-parse HEAD)
                RUN_ID=$(date +%s)

                # Generate common-nix.vars.pkr.hcl
                PG_VERSION=$(yq -r ".postgres_release[\"postgres$POSTGRES_VERSION\"]" ansible/vars.yml)
                echo "postgres-version = \"$PG_VERSION\"" > common-nix.vars.pkr.hcl

                # Build AMI Stage 1
                packer init amazon-arm64-nix.pkr.hcl
                packer build \
                  -var "git-head-version=$GIT_SHA" \
                  -var "packer-execution-id=$RUN_ID" \
                  -var-file="development-arm.vars.pkr.hcl" \
                  -var-file="common-nix.vars.pkr.hcl" \
                  -var "ansible_arguments=" \
                  -var "postgres-version=$RANDOM_STRING" \
                  -var "region=$REGION" \
                  -var 'ami_regions=["'"$REGION"'"]' \
                  -var "force-deregister=true" \
                  -var "ansible_arguments=-e postgresql_major=$POSTGRES_VERSION" \
                  amazon-arm64-nix.pkr.hcl

                # Build AMI Stage 2
                packer init stage2-nix-psql.pkr.hcl
                packer build \
                  -var "git-head-version=$GIT_SHA" \
                  -var "packer-execution-id=$RUN_ID" \
                  -var "postgres_major_version=$POSTGRES_VERSION" \
                  -var-file="development-arm.vars.pkr.hcl" \
                  -var-file="common-nix.vars.pkr.hcl" \
                  -var "postgres-version=$RANDOM_STRING" \
                  -var "region=$REGION" \
                  -var 'ami_regions=["'"$REGION"'"]' \
                  -var "force-deregister=true" \
                  -var "git_sha=$GIT_SHA" \
                  stage2-nix-psql.pkr.hcl

                # Cleanup instances from AMI builds
                cleanup_instances() {
                  echo "Terminating EC2 instances with tag testinfra-run-id=$RUN_ID..."
                  aws ec2 --region $REGION describe-instances \
                    --filters "Name=tag:testinfra-run-id,Values=$RUN_ID" \
                    --query "Reservations[].Instances[].InstanceId" \
                    --output text | xargs -r aws ec2 terminate-instances \
                    --region $REGION --instance-ids || true
                }

                # Set up traps for various signals to ensure cleanup
                trap cleanup_instances EXIT HUP INT QUIT TERM

                # Create and activate virtual environment
                VENV_DIR=$(mktemp -d)
                trap 'rm -rf "$VENV_DIR"' EXIT HUP INT QUIT TERM
                python3 -m venv "$VENV_DIR"
                source "$VENV_DIR/bin/activate"

                # Install required Python packages
                echo "Installing required Python packages..."
                pip install boto3 boto3-stubs[essential] docker ec2instanceconnectcli pytest paramiko requests

                # Run the tests with aws-vault
                echo "Running tests for AMI: $RANDOM_STRING using AWS Vault profile: $AWS_VAULT_PROFILE"
                aws-vault exec $AWS_VAULT_PROFILE -- pytest -vv -s testinfra/test_ami_nix.py

                # Deactivate virtual environment (cleanup is handled by trap)
                deactivate
                EOL
                chmod +x $out/bin/build-test-ami
              '';

            run-testinfra = pkgs.runCommand "run-testinfra"
              {
                buildInputs = with pkgs; [
                  aws-vault
                  python3
                  python3Packages.pip
                  coreutils
                ];
              } ''
                mkdir -p $out/bin
                cat > $out/bin/run-testinfra << 'EOL'
                #!/usr/bin/env bash
                set -euo pipefail

                show_help() {
                  cat << EOF
                Usage: run-testinfra --ami-name NAME [--aws-vault-profile PROFILE]

                Run the testinfra tests locally against a specific AMI.

                This script will:
                1. Check if aws-vault is installed and configured
                2. Set up the required environment variables
                3. Create and activate a virtual environment
                4. Install required Python packages from pip
                5. Run the tests with aws-vault credentials
                6. Clean up the virtual environment

                Required flags:
                  --ami-name NAME              The name of the AMI to test

                Optional flags:
                  --aws-vault-profile PROFILE  AWS Vault profile to use (default: staging)
                  --help                       Show this help message and exit

                Requirements:
                  - aws-vault installed and configured
                  - Python 3 with pip
                  - Must be run from the repository root

                Examples:
                  run-testinfra --ami-name supabase-postgres-abc123
                  run-testinfra --ami-name supabase-postgres-abc123 --aws-vault-profile production
                EOF
                }

                # Default values
                AWS_VAULT_PROFILE="staging"
                AMI_NAME=""

                # Parse arguments
                while [[ $# -gt 0 ]]; do
                  case $1 in
                    --aws-vault-profile)
                      AWS_VAULT_PROFILE="$2"
                      shift 2
                      ;;
                    --ami-name)
                      AMI_NAME="$2"
                      shift 2
                      ;;
                    --help)
                      show_help
                      exit 0
                      ;;
                    *)
                      echo "Error: Unexpected argument: $1"
                      show_help
                      exit 1
                      ;;
                  esac
                done

                # Check for required tools
                if ! command -v aws-vault &> /dev/null; then
                  echo "Error: aws-vault is required but not found"
                  exit 1
                fi

                # Check for AMI name argument
                if [ -z "$AMI_NAME" ]; then
                  echo "Error: --ami-name is required"
                  show_help
                  exit 1
                fi

                # Set environment variables
                export AWS_REGION="ap-southeast-1"
                export AWS_DEFAULT_REGION="ap-southeast-1"
                export AMI_NAME="$AMI_NAME"  # Export AMI_NAME for pytest
                export RUN_ID="local-$(date +%s)"  # Generate a unique RUN_ID

                # Function to terminate EC2 instances
                terminate_instances() {
                  echo "Terminating EC2 instances with tag testinfra-run-id=$RUN_ID..."
                  aws-vault exec $AWS_VAULT_PROFILE -- aws ec2 --region ap-southeast-1 describe-instances \
                    --filters "Name=tag:testinfra-run-id,Values=$RUN_ID" \
                    --query "Reservations[].Instances[].InstanceId" \
                    --output text | xargs -r aws-vault exec $AWS_VAULT_PROFILE -- aws ec2 terminate-instances \
                    --region ap-southeast-1 --instance-ids || true
                }

                # Set up traps for various signals to ensure cleanup
                trap terminate_instances EXIT HUP INT QUIT TERM

                # Create and activate virtual environment
                VENV_DIR=$(mktemp -d)
                trap 'rm -rf "$VENV_DIR"' EXIT HUP INT QUIT TERM
                python3 -m venv "$VENV_DIR"
                source "$VENV_DIR/bin/activate"

                # Install required Python packages
                echo "Installing required Python packages..."
                pip install boto3 boto3-stubs[essential] docker ec2instanceconnectcli pytest paramiko requests

                # Function to run tests and ensure cleanup
                run_tests() {
                  local exit_code=0
                  echo "Running tests for AMI: $AMI_NAME using AWS Vault profile: $AWS_VAULT_PROFILE"
                  aws-vault exec "$AWS_VAULT_PROFILE" -- pytest -vv -s testinfra/test_ami_nix.py || exit_code=$?
                  return $exit_code
                }

                # Run tests and capture exit code
                run_tests
                test_exit_code=$?

                # Deactivate virtual environment
                deactivate

                # Explicitly call cleanup
                terminate_instances

                # Exit with the test exit code
                exit $test_exit_code
                EOL
                chmod +x $out/bin/run-testinfra
              '';

            cleanup-ami = pkgs.runCommand "cleanup-ami"
              {
                buildInputs = with pkgs; [
                  awscli2
                  aws-vault
                ];
              } ''
                mkdir -p $out/bin
                cat > $out/bin/cleanup-ami << 'EOL'
                #!/usr/bin/env bash
                set -euo pipefail

                export PATH="${pkgs.lib.makeBinPath (with pkgs; [
                  awscli2
                  aws-vault
                ])}:$PATH"

                # Check for required tools
                for cmd in aws-vault; do
                  if ! command -v $cmd &> /dev/null; then
                    echo "Error: $cmd is required but not found"
                    exit 1
                  fi
                done

                # Check AWS Vault profile
                if [ -z "''${AWS_VAULT:-}" ]; then
                  echo "Error: AWS_VAULT environment variable must be set with the profile name"
                  echo "Usage: aws-vault exec <profile-name> -- nix run .#cleanup-ami <ami-name>"
                  exit 1
                fi

                # Check for AMI name argument
                if [ -z "''${1:-}" ]; then
                  echo "Error: AMI name must be provided"
                  echo "Usage: aws-vault exec <profile-name> -- nix run .#cleanup-ami <ami-name>"
                  exit 1
                fi

                AMI_NAME="$1"
                REGION="ap-southeast-1"

                # Deregister AMIs
                for AMI_PATTERN in "supabase-postgres-ci-ami-test-stage-1" "$AMI_NAME"; do
                  aws ec2 describe-images --region $REGION --owners self \
                    --filters "Name=name,Values=$AMI_PATTERN" \
                    --query 'Images[*].ImageId' --output text | while read -r ami_id; do
                      echo "Deregistering AMI: $ami_id"
                      aws ec2 deregister-image --region $REGION --image-id "$ami_id" || true
                    done
                done
                EOL
                chmod +x $out/bin/cleanup-ami
              '';

            trigger-nix-build = pkgs.runCommand "trigger-nix-build"
              {
                buildInputs = with pkgs; [
                  gh
                  git
                  coreutils
                ];
              } ''
                mkdir -p $out/bin
                cat > $out/bin/trigger-nix-build << 'EOL'
                #!/usr/bin/env bash
                set -euo pipefail

                show_help() {
                  cat << EOF
                Usage: trigger-nix-build [--help]

                Trigger the nix-build workflow for the current branch and watch its progress.

                This script will:
                1. Check if you're authenticated with GitHub
                2. Get the current branch and commit
                3. Verify you're on a standard branch (develop or release/*) or prompt for confirmation
                4. Trigger the nix-build workflow
                5. Watch the workflow progress until completion

                Options:
                  --help    Show this help message and exit

                Requirements:
                  - GitHub CLI (gh) installed and authenticated
                  - Git installed
                  - Must be run from a git repository

                Example:
                  trigger-nix-build
                EOF
                }

                # Handle help flag
                if [[ "$#" -gt 0 && "$1" == "--help" ]]; then
                  show_help
                  exit 0
                fi

                export PATH="${pkgs.lib.makeBinPath (with pkgs; [
                  gh
                  git
                  coreutils
                ])}:$PATH"

                # Check for required tools
                for cmd in gh git; do
                  if ! command -v $cmd &> /dev/null; then
                    echo "Error: $cmd is required but not found"
                    exit 1
                  fi
                done

                # Check if user is authenticated with GitHub
                if ! gh auth status &>/dev/null; then
                  echo "Error: Not authenticated with GitHub. Please run 'gh auth login' first."
                  exit 1
                fi

                # Get current branch and commit
                BRANCH=$(git rev-parse --abbrev-ref HEAD)
                COMMIT=$(git rev-parse HEAD)

                # Check if we're on a standard branch
                if [[ "$BRANCH" != "develop" && ! "$BRANCH" =~ ^release/ ]]; then
                  echo "Warning: Running workflow from non-standard branch: $BRANCH"
                  echo "This is supported for testing purposes."
                  read -p "Continue? [y/N] " -n 1 -r
                  echo
                  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                    echo "Aborted."
                    exit 1
                  fi
                fi

                # Trigger the workflow
                echo "Triggering nix-build workflow for branch $BRANCH (commit: $COMMIT)"
                gh workflow run nix-build.yml --ref "$BRANCH"

                # Wait for workflow to start and get the run ID
                echo "Waiting for workflow to start..."
                sleep 5

                # Get the latest run ID for this workflow
                RUN_ID=$(gh run list --workflow=nix-build.yml --limit 1 --json databaseId --jq '.[0].databaseId')

                if [ -z "$RUN_ID" ]; then
                  echo "Error: Could not find workflow run ID"
                  exit 1
                fi

                echo "Watching workflow run $RUN_ID..."
                echo "The script will automatically exit when the workflow completes."
                echo "Press Ctrl+C to stop watching (workflow will continue running)"
                echo "----------------------------------------"

                # Try to watch the run, but handle network errors gracefully
                while true; do
                  if gh run watch "$RUN_ID" --exit-status; then
                    break
                  else
                    echo "Network error while watching workflow. Retrying in 5 seconds..."
                    echo "You can also check the status manually with: gh run view $RUN_ID"
                    sleep 5
                  fi
                done
                EOL
                chmod +x $out/bin/trigger-nix-build
              '';
          };


        # Create a testing harness for a PostgreSQL package. This is used for
        # 'nix flake check', and works with any PostgreSQL package you hand it.

        makeCheckHarness = pgpkg:
          let
            sqlTests = ./nix/tests/smoke;
            pg_prove = pkgs.perlPackages.TAPParserSourceHandlerpgTAP;
            pg_regress = basePackages.pg_regress;
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
            start-postgres-server-bin = makePostgresDevSetup {
              inherit pkgs;
              name = "start-postgres-server-test";
              extraSubstitutions = {
                PGSODIUM_GETKEY = "${getkey-script}/bin/pgsodium-getkey";
                PGSQL_DEFAULT_PORT = pgPort;
              };
            };

            getVersionArg = pkg:
              let
                name = pkg.version;
              in
              if builtins.match "15.*" name != null then "15"
              else if builtins.match "17.*" name != null then "17"
              else if builtins.match "orioledb-17.*" name != null then "orioledb-17"
              else throw "Unsupported PostgreSQL version: ${name}";

            # Helper function to filter SQL files based on version
            filterTestFiles = version: dir:
              let
                files = builtins.readDir dir;
                isValidFile = name:
                  let
                    isVersionSpecific = builtins.match "z_.*" name != null;
                    matchesVersion =
                      if isVersionSpecific
                      then
                        if version == "orioledb-17"
                        then builtins.match "z_orioledb-17_.*" name != null
                        else if version == "17"
                        then builtins.match "z_17_.*" name != null
                        else builtins.match "z_15_.*" name != null
                      else true;
                  in
                  pkgs.lib.hasSuffix ".sql" name && matchesVersion;
              in
              pkgs.lib.filterAttrs (name: _: isValidFile name) files;

            # Get the major version for filtering
            majorVersion =
              let
                version = builtins.trace "pgpkg.version is: ${pgpkg.version}" pgpkg.version;
                _ = builtins.trace "Entering majorVersion logic";
                isOrioledbMatch = builtins.match "^17_[0-9]+$" version != null;
                isSeventeenMatch = builtins.match "^17[.][0-9]+$" version != null;
                result =
                  if isOrioledbMatch
                  then "orioledb-17"
                  else if isSeventeenMatch
                  then "17"
                  else "15";
              in
              builtins.trace "Major version result: ${result}" result; # Trace the result                                             # For "15.8"

            # Filter SQL test files
            filteredSqlTests = filterTestFiles majorVersion ./nix/tests/sql;

            pgPort = if (majorVersion == "17") then
                "5535"
                else if (majorVersion == "15") then
                "5536"
                else "5537";

            # Convert filtered tests to a sorted list of basenames (without extension)
            testList = pkgs.lib.mapAttrsToList
              (name: _:
                builtins.substring 0 (pkgs.lib.stringLength name - 4) name
              )
              filteredSqlTests;
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
            } ''
            set -e

            #First we need to create a generic pg cluster for pgtap tests and run those
            export GRN_PLUGINS_DIR=${supabase-groonga}/lib/groonga/plugins
            PGTAP_CLUSTER=$(mktemp -d)
            initdb --locale=C --username=supabase_admin -D "$PGTAP_CLUSTER"
            substitute ${./nix/tests/postgresql.conf.in} "$PGTAP_CLUSTER"/postgresql.conf \
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
              if pg_isready -h ${pgsqlDefaultHost} -p ${pgPort}; then
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
            createdb -p ${pgPort} -h ${pgsqlDefaultHost} --username=supabase_admin testing
            if ! psql -p ${pgPort} -h ${pgsqlDefaultHost} --username=supabase_admin -d testing -v ON_ERROR_STOP=1 -Xf ${./nix/tests/prime.sql}; then
              echo "Error executing SQL file. PostgreSQL log content:"
              cat "$PGTAP_CLUSTER"/postgresql.log
              pg_ctl -D "$PGTAP_CLUSTER" stop
              exit 1
            fi
            SORTED_DIR=$(mktemp -d)
            for t in $(printf "%s\n" ${builtins.concatStringsSep " " sortedTestList}); do
              psql -p ${pgPort} -h ${pgsqlDefaultHost} --username=supabase_admin -d testing -f "${./nix/tests/sql}/$t.sql" || true
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
                if pg_isready -h ${pgsqlDefaultHost} -p ${pgPort} -U supabase_admin -q; then
                    echo "PostgreSQL is ready"
                    break
                fi
                sleep 1
                if [ $i -eq 60 ]; then
                    echo "PostgreSQL failed to start"
                    exit 1
                fi
            done

            if ! psql -p ${pgPort} -h ${pgsqlDefaultHost} --no-password --username=supabase_admin -d postgres -v ON_ERROR_STOP=1 -Xf ${./nix/tests/prime.sql}; then
              echo "Error executing SQL file"
              exit 1
            fi

            mkdir -p $out/regression_output
            if ! pg_regress \
              --use-existing \
              --dbname=postgres \
              --inputdir=${./nix/tests} \
              --outputdir=$out/regression_output \
              --host=${pgsqlDefaultHost} \
              --port=${pgPort} \
              --user=supabase_admin \
              ${builtins.concatStringsSep " " sortedTestList}; then
              echo "pg_regress tests failed"
              cat $out/regression_output/regression.diffs
              exit 1
            fi

            echo "Running migrations tests"
            pg_prove -p ${pgPort} -U supabase_admin -h ${pgsqlDefaultHost} -d postgres -v ${./migrations/tests}/test.sql

            # Copy logs to output
            for logfile in $(find /tmp -name postgresql.log -type f); do
              cp "$logfile" $out/postgresql.log
            done
            exit 0
          '';
      in
      rec {
        # The list of all packages that can be built with 'nix build'. The list
        # of names that can be used can be shown with 'nix flake show'
        packages = flake-utils.lib.flattenTree basePackages // {
          # Any extra packages we might want to include in our package
          # set can go here.
          inherit (pkgs);
        };

        # The list of exported 'checks' that are run with every run of 'nix
        # flake check'. This is run in the CI system, as well.
        checks = {
          psql_15 = makeCheckHarness basePackages.psql_15.bin;
          psql_17 = makeCheckHarness basePackages.psql_17.bin;
          psql_orioledb-17 = makeCheckHarness basePackages.psql_orioledb-17.bin;
          inherit (basePackages) wal-g-2 wal-g-3 dbmate-tool pg_regress;
        } // pkgs.lib.optionalAttrs (system == "aarch64-linux") {
          inherit (basePackages) postgresql_15_debug postgresql_15_src postgresql_orioledb-17_debug postgresql_orioledb-17_src postgresql_17_debug postgresql_17_src;
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
            # migrate-postgres = mkApp "migrate-tool" "migrate-postgres";
            # sync-exts-versions = mkApp "sync-exts-versions" "sync-exts-versions";
            pg-restore = mkApp "pg-restore" "pg-restore";
            local-infra-bootstrap = mkApp "local-infra-bootstrap" "local-infra-bootstrap";
            dbmate-tool = mkApp "dbmate-tool" "dbmate-tool";
            update-readme = mkApp "update-readme" "update-readme";
            show-commands = mkApp "show-commands" "show-commands";
            build-test-ami = mkApp "build-test-ami" "build-test-ami";
            run-testinfra = mkApp "run-testinfra" "run-testinfra";
            cleanup-ami = mkApp "cleanup-ami" "cleanup-ami";
            trigger-nix-build = mkApp "trigger-nix-build" "trigger-nix-build";
          };

        # 'devShells.default' lists the set of packages that are included in the
        # ambient $PATH environment when you run 'nix develop'. This is useful
        # for development and puts many convenient devtools instantly within
        # reach.

        devShells =
          let
            mkCargoPgrxDevShell = { pgrxVersion, rustVersion }: pkgs.mkShell {
              packages = with pkgs; [
                basePackages."cargo-pgrx_${pgrxVersion}"
                (rust-bin.stable.${rustVersion}.default.override {
                  extensions = [ "rust-src" ];
                })
              ];
              shellHook = ''
                export HISTFILE=.history
              '';
            };
          in
          {
            default = pkgs.mkShell {
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
                basePackages.build-test-ami
                basePackages.run-testinfra
                basePackages.cleanup-ami
                dbmate
                nushell
                pythonEnv
                nix-fast-build
              ];
              shellHook = ''
                export HISTFILE=.history
              '';
            };
            cargo-pgrx_0_11_3 = mkCargoPgrxDevShell {
              pgrxVersion = "0_11_3";
              rustVersion = "1.80.0";
            };
            cargo-pgrx_0_12_6 = mkCargoPgrxDevShell {
              pgrxVersion = "0_12_6";
              rustVersion = "1.80.0";
            };
          };
      }
    );
}
