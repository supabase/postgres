{ self, inputs, ... }:
{
  perSystem =
    {
      inputs',
      lib,
      pkgs,
      self',
      system,
      ...
    }:
    let
      nix2container = inputs'.nix2container.packages.nix2container;

      # Build skopeo with nix: transport support (works on darwin and linux)
      # This is the same approach nix2container uses internally
      nix2container-bin = pkgs.buildGoModule {
        pname = "nix2container";
        version = "1.0.0";
        src = inputs.nix2container;
        sourceRoot = "source";
        vendorHash = "sha256-/j4ZHOwU5Xi8CE/fHha+2iZhsLd/y2ovzVhvg8HDV78=";
        ldflags = lib.optional pkgs.stdenv.isDarwin "-X github.com/nlewo/nix2container/nix.useNixCaseHack=true";
      };

      skopeo-nix = pkgs.skopeo.overrideAttrs (old: {
        EXTRA_LDFLAGS = lib.optionalString pkgs.stdenv.isDarwin "-X github.com/nlewo/nix2container/nix.useNixCaseHack=true";
        nativeBuildInputs = old.nativeBuildInputs ++ [ pkgs.patchutils ];
        preBuild =
          let
            fetchgitpatch =
              args:
              pkgs.fetchpatch2 (
                args
                // {
                  postFetch =
                    (args.postFetch or "")
                    + ''
                      sed -i \
                        -e '/^index /d' \
                        -e '/^similarity index /d' \
                        -e '/^dissimilarity index /d' \
                        $out
                    '';
                }
              );
            patch = fetchgitpatch {
              url = "https://github.com/nlewo/image/commit/c2254c998433cf02af60bf0292042bd80b96a77e.patch";
              sha256 = "sha256-6CUjz46xD3ORgwrHwdIlSu6JUj7WLS6BOSyRGNnALHY=";
            };
          in
          ''
            mkdir -p vendor/github.com/nlewo/nix2container/
            cp -r ${nix2container-bin.src}/* vendor/github.com/nlewo/nix2container/
            cd vendor/github.com/containers/image/v5
            mkdir -p nix/
            touch nix/transport.go
            filterdiff -x '*/alltransports.go' ${patch} | patch -p1
            sed -i '\#_ "github.com/containers/image/v5/tarball"#a _ "github.com/containers/image/v5/nix"' transports/alltransports/alltransports.go
            cd -

            echo '# github.com/nlewo/nix2container v1.0.0' >> vendor/modules.txt
            echo '## explicit; go 1.13' >> vendor/modules.txt
            echo github.com/nlewo/nix2container/nix >> vendor/modules.txt
            echo github.com/nlewo/nix2container/types >> vendor/modules.txt
            echo github.com/containers/image/v5/nix >> vendor/modules.txt
            echo 'require (' >> go.mod
            echo '  github.com/nlewo/nix2container v1.0.0' >> go.mod
            echo ')' >> go.mod
          '';
      });

      # Import helper modules (only for Linux where images are built)
      ubuntuBase = import ./base.nix { inherit nix2container system; };
      gosu = import ./gosu.nix { inherit pkgs system; };
      entrypoint = import ./entrypoint.nix { inherit pkgs; };
      usrbinCompat = import ./usrbin-compat.nix { inherit pkgs; };

      makePostgresConfigs =
        variant:
        import ./configs.nix {
          inherit lib pkgs variant;
          sourceRoot = self;
        };

      # Version tags from ansible/vars.yml
      versionTags = {
        "15" = "15.14.1.060";
        "17" = "17.6.1.060";
        "orioledb-17" = "17.6.0.017-orioledb";
      };

      makePostgresImage =
        { variant }:
        let
          pgPackage = self'.packages."psql_${variant}/bin";
          configs = makePostgresConfigs variant;
          tag = versionTags.${variant};
          isOrioledb = variant == "orioledb-17";
          isPg17 = variant == "17" || isOrioledb;
        in
        nix2container.buildImage {
          name = "supabase/postgres";
          inherit tag;

          fromImage = ubuntuBase;

          copyToRoot = pkgs.buildEnv {
            name = "postgres-root-${variant}";
            paths = [
              pgPackage
              self'.packages.supabase-groonga
              gosu
              entrypoint
              configs
              usrbinCompat
              # System utilities needed at runtime
              pkgs.coreutils
              pkgs.bash
              pkgs.gnused
              pkgs.gawk
              pkgs.findutils
              pkgs.gnugrep
              # Locale support - provides en_US.UTF-8
              pkgs.glibcLocales
            ];
            pathsToLink = [
              "/bin"
              "/lib"
              "/share"
              "/etc"
              "/usr"
              "/docker-entrypoint-initdb.d"
              "/home"
              "/root"
            ];
          };

          # Separate layer for PostgreSQL to optimize caching
          layers = [ (nix2container.buildLayer { deps = [ pgPackage ]; }) ];

          config = {
            Entrypoint = [ "/usr/local/bin/docker-entrypoint.sh" ];
            Cmd = [
              "postgres"
              "-D"
              "/etc/postgresql"
            ];
            ExposedPorts = {
              "5432/tcp" = { };
            };
            Env =
              [
                "PGDATA=/var/lib/postgresql/data"
                "POSTGRES_HOST=/var/run/postgresql"
                "POSTGRES_USER=supabase_admin"
                "POSTGRES_DB=postgres"
                "LANG=en_US.UTF-8"
                "LANGUAGE=en_US:en"
                "LC_ALL=en_US.UTF-8"
                # Point to nix glibc locales
                "LOCALE_ARCHIVE=${pkgs.glibcLocales}/lib/locale/locale-archive"
                "GRN_PLUGINS_DIR=/usr/lib/groonga/plugins"
                # Add PATH so postgres binaries are found
                "PATH=/bin:/usr/bin:/usr/local/bin"
              ]
              ++ lib.optionals isPg17 [
                "POSTGRES_INITDB_ARGS=--allow-group-access --locale-provider=icu --encoding=UTF-8 --icu-locale=en_US.UTF-8"
              ];
            # Start as root - entrypoint uses gosu to switch to postgres
            # This allows creating directories like /var/lib/postgresql at runtime
            WorkingDir = "/";
            StopSignal = "SIGINT";
          };
        };
      # Test script that loads and tests a Docker image (runs outside sandbox)
      # For darwin, we need to build the image for aarch64-linux but run the test script on darwin
      # Uses skopeo with nix: transport to load the image - works cross-platform
      makeDockerTestScript =
        { variant }:
        let
          tag = versionTags.${variant};
          containerName = "nix-test-postgres-${variant}";
          port =
            if variant == "15" then
              "15432"
            else if variant == "17" then
              "15433"
            else
              "15434";
          isOrioledb = variant == "orioledb-17";
          # Determine target architecture based on current system
          targetSystem = if system == "aarch64-darwin" then "aarch64-linux" else "x86_64-linux";
        in
        pkgs.writeShellApplication {
          name = "test-docker-postgres-${variant}";
          runtimeInputs = [
            pkgs.docker
            skopeo-nix
            pkgs.jq
          ];
          text = ''
            set -euo pipefail

            echo "=== Testing Docker image: supabase/postgres:${tag} ==="

            # Clean up any existing container from previous runs
            docker rm -f ${containerName} 2>/dev/null || true

            # Build the image JSON (this is cross-platform - just builds the manifest)
            echo "Building image manifest for ${targetSystem}..."
            IMAGE_JSON=$(nix build .#packages.${targetSystem}.\"docker/postgres-${variant}\" --print-out-paths --no-link)
            echo "Image manifest: $IMAGE_JSON"

            # Load the image into Docker using skopeo with nix: transport
            echo "Loading image into Docker daemon..."
            skopeo --insecure-policy copy "nix:$IMAGE_JSON" "docker-daemon:supabase/postgres:${tag}"

            echo "Starting container ${containerName}..."
            docker run -d \
              --name ${containerName} \
              -p ${port}:5432 \
              -e POSTGRES_PASSWORD=testpassword \
              supabase/postgres:${tag}

            cleanup() {
              echo "Cleaning up container..."
              docker stop ${containerName} || true
              docker rm ${containerName} || true
            }
            trap cleanup EXIT

            echo "Waiting for PostgreSQL to be ready..."
            for i in $(seq 1 60); do
              if docker exec ${containerName} pg_isready -U supabase_admin -h localhost -q 2>/dev/null; then
                echo "PostgreSQL is ready!"
                break
              fi
              if [ "$i" -eq 60 ]; then
                echo "PostgreSQL failed to start within 60 seconds"
                docker logs ${containerName}
                exit 1
              fi
              sleep 1
            done

            echo "Testing basic connectivity..."
            docker exec ${containerName} psql -h localhost -U supabase_admin -d postgres -c "SELECT version();"

            echo "Testing extension loading..."
            docker exec ${containerName} psql -h localhost -U supabase_admin -d postgres -c "CREATE EXTENSION IF NOT EXISTS vector;"
            docker exec ${containerName} psql -h localhost -U supabase_admin -d postgres -c "CREATE EXTENSION IF NOT EXISTS pg_stat_statements;"

            ${
              if isOrioledb then
                ''
                  echo "Testing OrioleDB extension..."
                  docker exec ${containerName} psql -h localhost -U supabase_admin -d postgres -c "CREATE EXTENSION IF NOT EXISTS orioledb;"
                ''
              else
                ''
                  echo "Testing PostGIS extension..."
                  docker exec ${containerName} psql -h localhost -U supabase_admin -d postgres -c "CREATE EXTENSION IF NOT EXISTS postgis;"
                ''
            }

            echo "=== All tests passed for postgres-${variant}! ==="
          '';
        };
    in
    {
      packages = lib.optionalAttrs (system == "aarch64-linux" || system == "x86_64-linux") {
        "docker/postgres-15" = makePostgresImage { variant = "15"; };
        "docker/postgres-17" = makePostgresImage { variant = "17"; };
        "docker/postgres-orioledb-17" = makePostgresImage { variant = "orioledb-17"; };
      };

      # Apps for running Docker image tests (outside of nix flake check)
      # Available on all systems - builds Linux image and loads into Docker
      apps = {
        "test-docker-postgres-15" = {
          type = "app";
          program = "${makeDockerTestScript { variant = "15"; }}/bin/test-docker-postgres-15";
        };
        "test-docker-postgres-17" = {
          type = "app";
          program = "${makeDockerTestScript { variant = "17"; }}/bin/test-docker-postgres-17";
        };
        "test-docker-postgres-orioledb-17" = {
          type = "app";
          program = "${
            makeDockerTestScript { variant = "orioledb-17"; }
          }/bin/test-docker-postgres-orioledb-17";
        };
      };
    };
}
