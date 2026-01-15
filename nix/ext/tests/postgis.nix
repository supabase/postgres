{ self, pkgs }:
let
  pname = "postgis";
  inherit (pkgs) lib;
  installedExtension =
    postgresMajorVersion:
    self.legacyPackages.${pkgs.stdenv.hostPlatform.system}."psql_${postgresMajorVersion}".exts."${
      pname
    }";
  versions = postgresqlMajorVersion: (installedExtension postgresqlMajorVersion).versions;
  postgresqlWithExtension =
    postgresql:
    let
      majorVersion = lib.versions.major postgresql.version;
      pkg = pkgs.buildEnv {
        name = "postgresql-${majorVersion}-${pname}";
        paths = [
          postgresql
          postgresql.lib
          (installedExtension majorVersion)
        ];
        passthru = {
          inherit (postgresql) version psqlSchema;
          installedExtensions = [ (installedExtension majorVersion) ];
          lib = pkg;
          withPackages = _: pkg;
          withJIT = pkg;
          withoutJIT = pkg;
        };
        nativeBuildInputs = [ pkgs.makeWrapper ];
        pathsToLink = [
          "/"
          "/bin"
          "/lib"
        ];
        postBuild = ''
          wrapProgram $out/bin/postgres --set NIX_PGLIBDIR $out/lib
          wrapProgram $out/bin/pg_ctl --set NIX_PGLIBDIR $out/lib
          wrapProgram $out/bin/pg_upgrade --set NIX_PGLIBDIR $out/lib
        '';
      };
    in
    pkg;
in
self.inputs.nixpkgs.lib.nixos.runTest {
  name = pname;
  hostPkgs = pkgs;
  nodes.server =
    { config, ... }:
    {
      virtualisation = {
        forwardPorts = [
          {
            from = "host";
            host.port = 13022;
            guest.port = 22;
          }
        ];
      };
      services.openssh = {
        enable = true;
      };

      services.postgresql = {
        enable = true;
        package = postgresqlWithExtension self.packages.${pkgs.stdenv.hostPlatform.system}.postgresql_15;
      };

      specialisation.postgresql17.configuration = {
        services.postgresql = {
          package = lib.mkForce (
            postgresqlWithExtension self.packages.${pkgs.stdenv.hostPlatform.system}.postgresql_17
          );
        };

        systemd.services.postgresql-migrate = {
          serviceConfig = {
            Type = "oneshot";
            RemainAfterExit = true;
            User = "postgres";
            Group = "postgres";
            StateDirectory = "postgresql";
            WorkingDirectory = "${builtins.dirOf config.services.postgresql.dataDir}";
          };
          script =
            let
              oldPostgresql =
                postgresqlWithExtension
                  self.packages.${pkgs.stdenv.hostPlatform.system}.postgresql_15;
              newPostgresql =
                postgresqlWithExtension
                  self.packages.${pkgs.stdenv.hostPlatform.system}.postgresql_17;
              oldDataDir = "${builtins.dirOf config.services.postgresql.dataDir}/${oldPostgresql.psqlSchema}";
              newDataDir = "${builtins.dirOf config.services.postgresql.dataDir}/${newPostgresql.psqlSchema}";
            in
            ''
              if [[ ! -d ${newDataDir} ]]; then
                install -d -m 0700 -o postgres -g postgres "${newDataDir}"
                ${newPostgresql}/bin/initdb -D "${newDataDir}"
                ${newPostgresql}/bin/pg_upgrade --old-datadir "${oldDataDir}" --new-datadir "${newDataDir}" \
                  --old-bindir "${oldPostgresql}/bin" --new-bindir "${newPostgresql}/bin"
              else
                echo "${newDataDir} already exists"
              fi
            '';
        };

        systemd.services.postgresql = {
          after = [ "postgresql-migrate.service" ];
          requires = [ "postgresql-migrate.service" ];
        };
      };
    };
  testScript =
    { nodes, ... }:
    let
      pg17-configuration = "${nodes.server.system.build.toplevel}/specialisation/postgresql17";
    in
    ''
      versions = {
        "15": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "15"))}],
        "17": [${lib.concatStringsSep ", " (map (s: ''"${s}"'') (versions "17"))}],
      }

      def run_sql(query):
        return server.succeed(f"""sudo -u postgres psql -t -A -F\",\" -c \"{query}\" """).strip()

      def check_upgrade_path(pg_version):
        with subtest("Check ${pname} upgrade path"):
          firstVersion = versions[pg_version][0]
          server.succeed("sudo -u postgres psql -c 'DROP EXTENSION IF EXISTS ${pname};'")
          run_sql(f"""CREATE EXTENSION ${pname} WITH VERSION '{firstVersion}' CASCADE;""")
          installed_version = run_sql(r"""SELECT extversion FROM pg_extension WHERE extname = '${pname}';""")
          assert installed_version == firstVersion, f"Expected ${pname} version {firstVersion}, but found {installed_version}"
          for version in versions[pg_version][1:]:
            run_sql(f"""ALTER EXTENSION ${pname} UPDATE TO '{version}';""")
            installed_version = run_sql(r"""SELECT extversion FROM pg_extension WHERE extname = '${pname}';""")
            assert installed_version == version, f"Expected ${pname} version {version}, but found {installed_version}"

      start_all()

      server.wait_for_unit("multi-user.target")
      server.wait_for_unit("postgresql.service")

      check_upgrade_path("15")

      with subtest("Check SFCGAL extension and functions"):
        # Create the SFCGAL extension
        run_sql("CREATE EXTENSION IF NOT EXISTS postgis_sfcgal CASCADE;")

        # Verify SFCGAL version is loaded
        sfcgal_version = run_sql("SELECT postgis_sfcgal_version();")
        assert sfcgal_version, f"SFCGAL version should not be empty, got: {sfcgal_version}"
        print(f"SFCGAL version: {sfcgal_version}")

        # Test ST_3DArea - compute area of a 3D polygon
        area_3d = run_sql("""
          SELECT ST_3DArea(
            ST_GeomFromText('POLYGON((0 0 0, 0 1 0, 1 1 0, 1 0 0, 0 0 0))')
          );
        """)
        assert float(area_3d) == 1.0, f"Expected 3D area of 1.0, got {area_3d}"

        # Test ST_StraightSkeleton - compute skeleton of a polygon
        skeleton = run_sql("""
          SELECT ST_AsText(
            ST_StraightSkeleton(
              ST_GeomFromText('POLYGON((0 0, 0 10, 10 10, 10 0, 0 0))')
            )
          );
        """)
        assert "MULTILINESTRING" in skeleton, f"Expected MULTILINESTRING skeleton, got {skeleton}"

        # Test ST_Tesselate - triangulate a polygon
        tesselate = run_sql("""
          SELECT ST_AsText(
            ST_Tesselate(
              ST_GeomFromText('POLYGON((0 0, 0 10, 10 10, 10 0, 0 0))')
            )
          );
        """)
        assert "TIN" in tesselate or "TRIANGLE" in tesselate, f"Expected TIN/TRIANGLE result, got {tesselate}"

        # Test ST_Extrude - extrude a 2D polygon to 3D
        extrude = run_sql("""
          SELECT ST_AsText(
            ST_Extrude(
              ST_GeomFromText('POLYGON((0 0, 0 1, 1 1, 1 0, 0 0))'),
              0, 0, 1
            )
          );
        """)
        assert "POLYHEDRALSURFACE" in extrude, f"Expected POLYHEDRALSURFACE from extrude, got {extrude}"

        # Test ST_Volume - compute volume of an extruded solid
        volume = run_sql("""
          SELECT ST_Volume(
            ST_Extrude(
              ST_GeomFromText('POLYGON((0 0, 0 1, 1 1, 1 0, 0 0))'),
              0, 0, 1
            )
          );
        """)
        assert float(volume) == 1.0, f"Expected volume of 1.0, got {volume}"

      with subtest("Check ${pname} latest extension version"):
        server.succeed("sudo -u postgres psql -c 'DROP EXTENSION ${pname};'")
        server.succeed("sudo -u postgres psql -c 'CREATE EXTENSION ${pname} CASCADE;'")
        installed_extensions=run_sql(r"""SELECT extname, extversion FROM pg_extension where extname = '${pname}';""")
        latestVersion = versions["15"][-1]
        majMinVersion = ".".join(latestVersion.split('.')[:1])
        assert f"${pname},{majMinVersion}" in installed_extensions, f"Expected ${pname} version {latestVersion}, but found {installed_extensions}"

      with subtest("switch to postgresql 17"):
        server.succeed(
          "${pg17-configuration}/bin/switch-to-configuration test >&2"
        )

      with subtest("Check ${pname} latest extension version after upgrade"):
        installed_extensions=run_sql(r"""SELECT extname, extversion FROM pg_extension;""")
        latestVersion = versions["17"][-1]
        majMinVersion = ".".join(latestVersion.split('.')[:1])
        assert f"${pname},{majMinVersion}" in installed_extensions

      with subtest("Check SFCGAL functions after PostgreSQL 17 upgrade"):
        # Verify SFCGAL extension still works after pg_upgrade
        run_sql("CREATE EXTENSION IF NOT EXISTS postgis_sfcgal CASCADE;")

        sfcgal_version = run_sql("SELECT postgis_sfcgal_version();")
        assert sfcgal_version, f"SFCGAL version should not be empty after upgrade, got: {sfcgal_version}"
        print(f"SFCGAL version on PG17: {sfcgal_version}")

        # Re-run core SFCGAL function tests on PG17
        area_3d = run_sql("""
          SELECT ST_3DArea(
            ST_GeomFromText('POLYGON((0 0 0, 0 1 0, 1 1 0, 1 0 0, 0 0 0))')
          );
        """)
        assert float(area_3d) == 1.0, f"Expected 3D area of 1.0 on PG17, got {area_3d}"

        volume = run_sql("""
          SELECT ST_Volume(
            ST_Extrude(
              ST_GeomFromText('POLYGON((0 0, 0 1, 1 1, 1 0, 0 0))'),
              0, 0, 1
            )
          );
        """)
        assert float(volume) == 1.0, f"Expected volume of 1.0 on PG17, got {volume}"

      check_upgrade_path("17")
    '';
}
