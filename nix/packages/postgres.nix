{
  self,
  inputs,
  ...
}:
{
  perSystem =
    { pkgs, ... }:
    let
      gitRev = "vcs=${self.shortRev or "dirty"}+${
        builtins.substring 0 8 (self.lastModifiedDate or self.lastModified or "19700101")
      }";

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
        ../ext/timescaledb-2.9.1.nix
        ../ext/pgroonga.nix
        ../ext/index_advisor.nix
        ../ext/wal2json.nix
        ../ext/pgmq.nix
        ../ext/pg_repack.nix
        ../ext/pg-safeupdate.nix
        ../ext/plpgsql-check.nix
        ../ext/pgjwt.nix
        ../ext/pgaudit.nix
        ../ext/postgis.nix
        ../ext/pgrouting.nix
        ../ext/pgtap.nix
        ../ext/pg_cron.nix
        ../ext/pgsql-http.nix
        ../ext/pg_plan_filter.nix
        ../ext/pg_net.nix
        ../ext/pg_hashids.nix
        ../ext/pgsodium.nix
        ../ext/pg_graphql.nix
        ../ext/pg_stat_monitor.nix
        ../ext/pg_jsonschema.nix
        ../ext/pgvector.nix
        ../ext/vault.nix
        ../ext/hypopg.nix
        ../ext/pg_tle.nix
        ../ext/wrappers/default.nix
        ../ext/supautils.nix
        ../ext/plv8.nix
      ];

      #Where we import and build the orioledb extension, we add on our custom extensions
      # plus the orioledb option
      #we're not using timescaledb or plv8 in the orioledb-17 version or pg 17 of supabase extensions
      orioleFilteredExtensions = builtins.filter (
        x: x != ../ext/timescaledb.nix && x != ../ext/timescaledb-2.9.1.nix && x != ../ext/plv8.nix
      ) ourExtensions;

      orioledbExtensions = orioleFilteredExtensions ++ [ ../ext/orioledb.nix ];
      dbExtensions17 = orioleFilteredExtensions;
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
            revision = gitRev;
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
        let
          postgresql = getPostgresqlPackage version;
          extensionsToUse =
            if (builtins.elem version [ "orioledb-17" ]) then
              orioledbExtensions
            else if (builtins.elem version [ "17" ]) then
              dbExtensions17
            else
              ourExtensions;
        in
        map (path: pkgs.callPackage path { inherit postgresql; }) extensionsToUse;

      # Create an attrset that contains all the extensions included in a server.
      makeOurPostgresPkgsSet =
        version:
        (builtins.listToAttrs (
          map (drv: {
            name = drv.pname;
            value = drv;
          }) (makeOurPostgresPkgs version)
        ))
        // {
          recurseForDerivations = true;
        };

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
        let
          postgresql = getPostgresqlPackage version;
          ourExts = map (ext: {
            name = ext.pname;
            version = ext.version;
          }) (makeOurPostgresPkgs version);

          pgbin = postgresql.withPackages (ps: makeOurPostgresPkgs version);
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
      makePostgres = version: {
        bin = makePostgresBin version;
        exts = makeOurPostgresPkgsSet version;
        recurseForDerivations = true;
      };
      basePackages = {
        psql_15 = makePostgres "15";
        psql_17 = makePostgres "17";
        psql_orioledb-17 = makePostgres "orioledb-17";
      };
    in
    {
      packages = inputs.flake-utils.lib.flattenTree basePackages;
    };
}
