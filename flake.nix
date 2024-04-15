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
      ];
    in
    flake-utils.lib.eachSystem ourSystems (system:
      let
        pgsqlDefaultPort = "5435";
        pgsqlSuperuser = "postgres";
        nix2img = nix2container.packages.${system}.nix2container;

        # The 'oriole_pkgs' variable holds all the upstream packages in nixpkgs, which
        # we can use to build our own images; it is the common name to refer to
        # a copy of nixpkgs which contains all its packages.
        # it also serves as a base for importing the orioldb/postgres overlay to 
        #build the orioledb postgres patched version of postgresql16
        oriole_pkgs = import nixpkgs {
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
          inherit system;
          overlays = [
            # NOTE (aseipp): add any needed overlays here. in theory we could
            # pull them from the overlays/ directory automatically, but we don't
            # want to have an arbitrary order, since it might matter. being
            # explicit is better.
            (import ./nix/overlays/cargo-pgrx-0-11-3.nix)
            #(import ./nix/overlays/gdal-small.nix)

          ];
        };


        # FIXME (aseipp): pg_prove is yet another perl program that needs
        # LOCALE_ARCHIVE set in non-NixOS environments. upstream this. once that's done, we
        # can remove this wrapper.
        pg_prove = pkgs.runCommand "pg_prove"
          {
            nativeBuildInputs = [ pkgs.makeWrapper ];
          } ''
          mkdir -p $out/bin
          for x in pg_prove pg_tapgen; do
            makeWrapper "${pkgs.perlPackages.TAPParserSourceHandlerpgTAP}/bin/$x" "$out/bin/$x" \
              --set LOCALE_ARCHIVE "${pkgs.glibcLocales}/lib/locale/locale-archive"
          done
        '';


        # Our list of PostgreSQL extensions which come from upstream Nixpkgs.
        # These are maintained upstream and can easily be used here just by
        # listing their name. Anytime the version of nixpkgs is upgraded, these
        # may also bring in new versions of the extensions.
        psqlExtensions = [
          /* pljava */
          "postgis"
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
          ./nix/ext/pgroonga.nix
          ./nix/ext/index_advisor.nix
          ./nix/ext/wal2json.nix
          ./nix/ext/pg_repack.nix
          ./nix/ext/pg-safeupdate.nix
          ./nix/ext/plpgsql-check.nix
          ./nix/ext/pgjwt.nix
          ./nix/ext/pgaudit.nix
          #./nix/ext/postgis.nix
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
        orioledbExtension = ourExtensions ++ [ ./nix/ext/orioledb.nix ];

        #this var is a convenience setting to import the orioledb patched version of postgresql
        postgresql_orioledb_16 = oriole_pkgs.postgresql_orioledb_16;
        postgis_override = pkgs.postgis_override;

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
          let postgresql = pkgs."postgresql_${version}";
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
            postgresql = pkgs."postgresql_${version}";
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

        # Make a Docker Image from a given PostgreSQL version and binary package.
        # updated to use https://github.com/nlewo/nix2container (samrose)
        makePostgresDocker = version: binPackage:
          let
            initScript = pkgs.runCommand "docker-init.sh" { } ''
              mkdir -p $out/bin
              substitute ${./nix/docker/init.sh.in} $out/bin/init.sh \
                --subst-var-by 'PGSQL_DEFAULT_PORT' '${pgsqlDefaultPort}'

              chmod +x $out/bin/init.sh
            '';

            postgresqlConfig = pkgs.runCommand "postgresql.conf" { } ''
              mkdir -p $out/etc/
              substitute ${./nix/tests/postgresql.conf.in} $out/etc/postgresql.conf \
                --subst-var-by 'PGSQL_DEFAULT_PORT' '${pgsqlDefaultPort}' \
                --subst-var-by PGSODIUM_GETKEY_SCRIPT "${./nix/tests/util/pgsodium_getkey.sh}"
            '';

            l = pkgs.lib // builtins;

            user = "postgres";
            group = "postgres";
            uid = "1001";
            gid = "1001";

            mkUser = pkgs.runCommand "mkUser" { } ''
              mkdir -p $out/etc/pam.d

              echo "${user}:x:${uid}:${gid}::" > $out/etc/passwd
              echo "${user}:!x:::::::" > $out/etc/shadow

              echo "${group}:x:${gid}:" > $out/etc/group
              echo "${group}:x::" > $out/etc/gshadow

              cat > $out/etc/pam.d/other <<EOF
              account sufficient pam_unix.so
              auth sufficient pam_rootok.so
              password requisite pam_unix.so nullok sha512
              session required pam_unix.so
              EOF

              touch $out/etc/login.defs
            '';
            run = pkgs.runCommand "run" { } ''
              mkdir -p $out/run/postgresql
            '';
            data = pkgs.runCommand "data" { } ''
              mkdir -p $out/data/postgresql
            '';
            pgconf = pkgs.runCommand "pgconf" { } ''
              mkdir -p $out/data/pgconf
            '';
          in
          nix2img.buildImage {
            name = "nix-experimental-postgresql-${version}-${system}";
            tag = "latest";

            nixUid = l.toInt uid;
            nixGid = l.toInt gid;

            copyToRoot = [
              (pkgs.buildEnv {
                name = "image-root";
                paths = [ data run pkgs.coreutils pkgs.which pkgs.bash pkgs.nix pkgs.less initScript binPackage postgresqlConfig pkgs.dockerTools.binSh pkgs.sudo ];
                pathsToLink = [ "/bin" "/etc" "/var" "/share" "/data" "/run" ];
              })
              mkUser
            ];

            perms = [
              {
                path = data;
                regex = "";
                mode = "0744";
                uid = l.toInt uid;
                gid = l.toInt gid;
                uname = user;
                gname = group;
              }
              {
                path = pgconf;
                regex = "";
                mode = "0744";
                uid = l.toInt uid;
                gid = l.toInt gid;
                uname = user;
                gname = group;
              }
              {
                path = run;
                regex = "";
                mode = "0744";
                uid = l.toInt uid;
                gid = l.toInt gid;
                uname = user;
                gname = group;
              }
            ];

            config = {
              Entrypoint = [ "/bin/init.sh" ];
              User = "postgres";
              WorkingDir = "/data";
              Env = [
                "NIX_PAGER=cat"
                "USER=postgres"
                "PGDATA=/data/postgresql"
                "PGHOST=/run/postgresql"
              ];
              ExposedPorts = { "${pgsqlDefaultPort}/tcp" = { }; };
              Volumes = { "/data" = { }; };
            };
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
        #  - docker: a docker image containing the postgresql package, with all
        #    the extensions installed, and a receipt.json file containing
        #    metadata about the install.
        makePostgres = version: rec {
          bin = makePostgresBin version;
          exts = makeOurPostgresPkgsSet version;
          docker = makePostgresDocker version bin;
          recurseForDerivations = true;
        };
        makeOrioleDbPostgres = version: patchedPostgres: rec {
          bin = makeOrioleDbPostgresBin version patchedPostgres;
          exts = makeOurOrioleDbPostgresPkgsSet version patchedPostgres;
          docker = makePostgresDocker version bin;
          recurseForDerivations = true;
        };

        # The base set of packages that we export from this Nix Flake, that can
        # be used with 'nix build'. Don't use the names listed below; check the
        # name in 'nix flake show' in order to make sure exactly what name you
        # want.
        basePackages = {
          # PostgreSQL versions.
          psql_15 = makePostgres "15";
          #psql_16 = makePostgres "16";
          #psql_orioledb_16 = makeOrioleDbPostgres "16_23" postgresql_orioledb_16;

          # Start a version of the server.
          start-server =
            let
              configFile = ./nix/tests/postgresql.conf.in;
              getkeyScript = ./nix/tests/util/pgsodium_getkey.sh;
            in
            pkgs.runCommand "start-postgres-server" { } ''
              mkdir -p $out/bin
              substitute ${./nix/tools/run-server.sh.in} $out/bin/start-postgres-server \
                --subst-var-by 'PGSQL_DEFAULT_PORT' '${pgsqlDefaultPort}' \
                --subst-var-by 'PGSQL_SUPERUSER' '${pgsqlSuperuser}' \
                --subst-var-by 'PSQL15_BINDIR' '${basePackages.psql_15.bin}' \
                --subst-var-by 'PSQL_CONF_FILE' '${configFile}' \
                --subst-var-by 'PGSODIUM_GETKEY' '${getkeyScript}'

              chmod +x $out/bin/start-postgres-server
            '';

          # Start a version of the client.
          start-client = pkgs.runCommand "start-postgres-client" { } ''
            mkdir -p $out/bin
            substitute ${./nix/tools/run-client.sh.in} $out/bin/start-postgres-client \
              --subst-var-by 'PGSQL_DEFAULT_PORT' '${pgsqlDefaultPort}' \
              --subst-var-by 'PGSQL_SUPERUSER' '${pgsqlSuperuser}' \
              --subst-var-by 'PSQL15_BINDIR' '${basePackages.psql_15.bin}'
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
              --subst-var-by 'PSQL15_BINDIR' '${basePackages.psql_15.bin}'\
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
          in
          pkgs.runCommand "postgres-${pgpkg.version}-check-harness"
            {
              nativeBuildInputs = with pkgs; [ coreutils bash pgpkg pg_prove procps ];
            } ''
            export PGDATA=/tmp/pgdata
            mkdir -p $PGDATA
            initdb --locale=C

            substitute ${./nix/tests/postgresql.conf.in} $PGDATA/postgresql.conf \
              --subst-var-by PGSODIUM_GETKEY_SCRIPT "${./nix/tests/util/pgsodium_getkey.sh}"

            postgres -k /tmp >logfile 2>&1 &
            sleep 2

            createdb -h localhost testing

            psql -h localhost -d testing -Xaf ${./nix/tests/prime.sql}
            pg_prove -h localhost -d testing ${sqlTests}/*.sql

            pkill postgres
            mv logfile $out
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
            pg_prove
            shellcheck

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
