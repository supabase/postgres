{ inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    let
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
        ../ext/rum.nix
        ../ext/timescaledb.nix
        ../ext/pgroonga
        ../ext/index_advisor.nix
        ../ext/wal2json.nix
        ../ext/pgmq
        ../ext/pg_repack.nix
        ../ext/pg-safeupdate.nix
        ../ext/plpgsql-check.nix
        ../ext/pgjwt.nix
        ../ext/pgaudit.nix
        ../ext/postgis.nix
        ../ext/pgrouting
        ../ext/pgtap.nix
        ../ext/pg_cron
        ../ext/pgsql-http.nix
        ../ext/pg_plan_filter.nix
        ../ext/pg_net.nix
        ../ext/pg_hashids.nix
        ../ext/pgsodium.nix
        ../ext/pg_graphql
        ../ext/pg_stat_monitor.nix
        ../ext/pg_jsonschema
        ../ext/pg_partman.nix
        ../ext/pgvector.nix
        ../ext/vault.nix
        ../ext/hypopg.nix
        ../ext/pg_tle.nix
        ../ext/wrappers/default.nix
        ../ext/supautils.nix
        ../ext/plv8
      ];

      #Where we import and build the orioledb extension, we add on our custom extensions
      # plus the orioledb option
      #we're not using timescaledb or plv8 in the orioledb-17 version or pg 17 of supabase extensions
      orioleFilteredExtensions = builtins.filter (
        x: x != ../ext/timescaledb.nix && x != ../ext/timescaledb-2.9.1.nix && x != ../ext/plv8
      ) ourExtensions;

      orioledbExtensions = orioleFilteredExtensions ++ [ ../ext/orioledb.nix ];
      dbExtensions17 = orioleFilteredExtensions;

      # CLI extensions - minimal set for Supabase CLI with migration support
      cliExtensions = [
        ../ext/supautils.nix
        ../ext/pg_graphql
        ../ext/pgsodium.nix
        ../ext/vault.nix
        ../ext/pg_net.nix
        ../ext/pg_cron
      ];

      getPostgresqlPackage = version: pkgs."postgresql_${version}";
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
      makeReceipt =
        pgbin: ourExts:
        pkgs.writeTextFile {
          name = "receipt";
          destination = "/receipt.json";
          text = builtins.toJSON {
            psql-version = pgbin.version;
            nixpkgs = {
              revision = inputs.nixpkgs.rev;
            };
            extensions = ourExts;

            # NOTE this field can be used to do cache busting (e.g.
            # force a rebuild of the psql packages) but also to helpfully inform
            # tools what version of the schema is being used, for forwards and
            # backwards compatibility
            receipt-version = "1";
          };
        };

      makeOurPostgresPkgs =
        version:
        {
          variant ? "full",
          postgresql ? getPostgresqlPackage version,
        }:
        let
          extensionsToUse =
            if variant == "cli" then
              cliExtensions
            else if (builtins.elem version [ "orioledb-17" ]) then
              orioledbExtensions
            else if (builtins.elem version [ "17" ]) then
              dbExtensions17
            else
              ourExtensions;
          extCallPackage = pkgs.lib.callPackageWith (
            pkgs
            // {
              inherit postgresql;
              switch-ext-version = extCallPackage ./switch-ext-version.nix { };
              overlayfs-on-package = extCallPackage ./overlayfs-on-package.nix { };
            }
          );
        in
        map (path: extCallPackage path { }) extensionsToUse;

      # Create an attrset that contains all the extensions included in a server.
      makeOurPostgresPkgsSet =
        version:
        {
          variant ? "full",
        }:
        let
          pkgsList = makeOurPostgresPkgs version { inherit variant; };
          baseAttrs = builtins.listToAttrs (
            map (drv: {
              name = drv.name;
              value = drv;
            }) pkgsList
          );
          # Expose individual packages from extensions that have them in passthru.packages
          # This makes them discoverable by nix-eval-jobs --force-recurse
          individualPkgs = lib.concatMapAttrs (
            name: drv: lib.optionalAttrs (drv ? passthru.packages) { "${name}-pkgs" = drv.passthru.packages; }
          ) baseAttrs;
        in
        baseAttrs // individualPkgs // { recurseForDerivations = true; };

      # Create a binary distribution of PostgreSQL, given a version.
      #
      # NOTE: The version here does NOT refer to the exact PostgreSQL version;
      # it refers to the *major number only*, which is used to select the
      # correct version of the package from nixpkgs. This is because we want
      # to be able to do so in an open ended way. As an example, the version
      # "15" passed in will use the nixpkgs package "postgresql_15" as the
      # basis for building extensions, etc.
      makePostgresBin =
        version:
        {
          variant ? "full",
        }:
        let
          basePostgresql = getPostgresqlPackage version;

          # For CLI variant, override postgresql to remove hardcoded /nix/store paths
          postgresql =
            if variant == "cli" then
              basePostgresql.overrideAttrs (oldAttrs: {
                #TODO:JAD Temporarily disable checks and tests for faster rebuilds - re-enable before final commit
                doCheck = false;
                doInstallCheck = false;

                # Filter out --with-system-tzdata to use bundled timezone data
                configureFlags = builtins.filter (
                  flag: !(lib.hasPrefix "--with-system-tzdata" flag)
                ) oldAttrs.configureFlags;

                # Filter out locale-binary-path.patch to avoid hardcoding locale path
                patches = builtins.filter (
                  patch:
                  let
                    patchName = baseNameOf (toString patch);
                  in
                  patchName != "locale-binary-path.patch"
                ) oldAttrs.patches;

                # Remove locale from buildInputs for Linux to prevent hardcoded paths
                buildInputs = builtins.filter (
                  input:
                  let
                    inputName = lib.getName input;
                  in
                  !lib.hasInfix "locale" inputName && inputName != "adv_cmds"
                ) (oldAttrs.buildInputs or [ ]);

                # Override postFixup to remove the initdb wrapper that hardcodes locale path
                postFixup =
                  lib.replaceStrings
                    [
                      ''
                        # Wrap initdb to set PGTZ
                        wrapProgram $out/bin/initdb --set PGTZ UTC
                      ''
                    ]
                    [
                      ''
                        # Skip initdb wrapper for CLI variant to avoid hardcoded locale paths
                        # The locale command will be resolved from system PATH at runtime
                      ''
                    ]
                    (oldAttrs.postFixup or "");

                # Add preConfigure to prevent autoconf from detecting system tzdata
                preConfigure = (oldAttrs.preConfigure or "") + ''
                  # For CLI variant: prevent configure from auto-detecting system timezone data
                  # We want to use the bundled timezone data for portability
                  export ac_cv_path_TZDATA_DIR=no
                '';
              })
            else
              basePostgresql;

          postgres-pkgs = makeOurPostgresPkgs version { inherit variant postgresql; };
          ourExts = map (ext: {
            name = ext.name;
            version = ext.version;
          }) postgres-pkgs;

          # For CLI variant, manually construct buildEnv to ensure our overridden postgresql is used
          pgbin =
            if variant == "cli" then
              let
                # Collect wrapper args from all extensions
                allWrapperArgs = lib.concatMap (ext: ext.passthru.wrapperArgs or [ ]) postgres-pkgs;
              in
              pkgs.buildEnv {
                name = "postgresql-and-plugins-${postgresql.version}";
                paths = [ postgresql ] ++ postgres-pkgs;
                buildInputs = [ pkgs.makeBinaryWrapper ];

                postBuild = ''
                  # Wrap postgres binary with extension wrapper args
                  if [ -f "$out/bin/postgres" ]; then
                    mv "$out/bin/postgres" "$out/bin/.postgres-wrapped"
                    makeWrapper "$out/bin/.postgres-wrapped" "$out/bin/postgres" \
                      --set NIX_PGLIBDIR "$out/lib" \
                      ${lib.concatStringsSep " " allWrapperArgs}
                  fi

                  # Wrap other binaries with NIX_PGLIBDIR
                  for binary in initdb pg_ctl psql; do
                    if [ -f "$out/bin/$binary" ]; then
                      mv "$out/bin/$binary" "$out/bin/.$binary-wrapped"
                      makeWrapper "$out/bin/.$binary-wrapped" "$out/bin/$binary" \
                        --set NIX_PGLIBDIR "$out/lib"
                    fi
                  done
                '';

                passthru = postgresql.passthru // {
                  inherit (postgresql) psqlSchema version;
                  withPackages = throw "Use manual buildEnv for CLI variant";
                };
              }
            else
              postgresql.withPackages (_ps: postgres-pkgs);
        in
        pkgs.symlinkJoin {
          inherit (pgbin) name version;
          paths = [
            pgbin
            (makeReceipt pgbin ourExts)
          ];
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
      makePostgres =
        version:
        {
          variant ? "full",
        }:
        lib.recurseIntoAttrs {
          bin = makePostgresBin version { inherit variant; };
          exts = makeOurPostgresPkgsSet version { inherit variant; };
        };
      basePackages = {
        psql_15 = makePostgres "15" { };
        psql_17 = makePostgres "17" { };
        psql_orioledb-17 = makePostgres "orioledb-17" { };
      };

      # CLI packages - minimal PostgreSQL + supautils only for Supabase CLI
      cliPackages = {
        psql_17_cli = makePostgres "17" { variant = "cli"; };
      };

      binPackages = lib.mapAttrs' (name: value: {
        name = "${name}/bin";
        value = value.bin;
      }) (basePackages // cliPackages);
    in
    {
      packages = binPackages;
      legacyPackages = basePackages // cliPackages;
    };
}
