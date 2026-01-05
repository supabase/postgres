{ self, inputs, ... }:
{
  imports = [ ./postgres.nix ];
  perSystem =
    {
      inputs',
      lib,
      pkgs,
      self',
      ...
    }:
    let
      activeVersion = "15";
      # Function to create the pg_regress package
      makePgRegress =
        version:
        let
          postgresqlPackage = self'.packages."postgresql_${version}";
        in
        pkgs.callPackage ../ext/pg_regress.nix { postgresql = postgresqlPackage; };
      pgsqlSuperuser = "supabase_admin";
      supascan-pkgs = pkgs.callPackage ./supascan.nix {
        inherit (pkgs) lib;
        inherit inputs;
      };
      pkgs-lib = pkgs.callPackage ./lib.nix {
        psql_15 = self'.packages."psql_15/bin";
        psql_17 = self'.packages."psql_17/bin";
        psql_orioledb-17 = self'.packages."psql_orioledb-17/bin";
        inherit (self.supabase) defaults;
      };
    in
    {
      packages = (
        {
          build-ami = pkgs.callPackage ./build-ami.nix { packer = self'.packages.packer; };
          build-test-ami = pkgs.callPackage ./build-test-ami.nix { };
          cleanup-ami = pkgs.callPackage ./cleanup-ami.nix { };
          dbmate-tool = pkgs.callPackage ./dbmate-tool.nix { inherit (self.supabase) defaults; };
          docs = pkgs.callPackage ./docs.nix { };
          github-matrix = pkgs.callPackage ./github-matrix {
            nix-eval-jobs = inputs'.nix-eval-jobs.packages.default;
          };
          supabase-groonga = pkgs.callPackage ../ext/pgroonga/groonga.nix { };
          http-mock-server = pkgs.callPackage ./http-mock-server.nix { };
          local-infra-bootstrap = pkgs.callPackage ./local-infra-bootstrap.nix { };
          mecab-naist-jdic = pkgs.callPackage ./mecab-naist-jdic.nix { };
          migrate-tool = pkgs.callPackage ./migrate-tool.nix { psql_15 = self'.packages."psql_15/bin"; };
          overlayfs-on-package = pkgs.callPackage ./overlayfs-on-package.nix { };
          packer = pkgs.callPackage ./packer.nix { inherit inputs; };
          pg-backrest = inputs.nixpkgs.legacyPackages.${pkgs.stdenv.hostPlatform.system}.pgbackrest;
          pg-restore = pkgs.callPackage ./pg-restore.nix { psql_15 = self'.packages."psql_15/bin"; };
          pg_prove = pkgs.perlPackages.TAPParserSourceHandlerpgTAP;
          pg_regress = makePgRegress activeVersion;
          run-testinfra = pkgs.callPackage ./run-testinfra.nix { };
          show-commands = pkgs.callPackage ./show-commands.nix { };
          start-client = pkgs.callPackage ./start-client.nix {
            psql_15 = self'.packages."psql_15/bin";
            psql_17 = self'.packages."psql_17/bin";
            psql_orioledb-17 = self'.packages."psql_orioledb-17/bin";
            inherit (self.supabase) defaults;
          };
          start-replica = pkgs.callPackage ./start-replica.nix {
            psql_15 = self'.packages."psql_15/bin";
            inherit pgsqlSuperuser;
          };
          start-server = pkgs-lib.makePostgresDevSetup {
            inherit pkgs;
            name = "start-postgres-server";
            pgroonga = self'.legacyPackages."psql_${activeVersion}".exts.pgroonga;
          };
          switch-ext-version = pkgs.callPackage ./switch-ext-version.nix {
            inherit (self'.packages) overlayfs-on-package;
          };
          sync-exts-versions = pkgs.callPackage ./sync-exts-versions.nix { inherit (inputs') nix-editor; };
          trigger-nix-build = pkgs.callPackage ./trigger-nix-build.nix { };
          update-readme = pkgs.callPackage ./update-readme.nix { };
          inherit (pkgs.callPackage ./wal-g.nix { }) wal-g-2;
          inherit (supascan-pkgs) goss supascan supascan-specs;
          inherit (pkgs.cargo-pgrx)
            cargo-pgrx_0_11_3
            cargo-pgrx_0_12_6
            cargo-pgrx_0_12_9
            cargo-pgrx_0_14_3
            ;
        }
        // lib.filterAttrs (n: _v: n != "override" && n != "overrideAttrs" && n != "overrideDerivation") (
          pkgs.callPackage ../postgresql/default.nix {
            inherit self';
            inherit (self.supabase) supportedPostgresVersions;
          }
        )
      );
    };
}
