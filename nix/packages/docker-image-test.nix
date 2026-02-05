{
  writeShellApplication,
  coreutils,
  gnused,
  python3,
  psql_15,
  psql_17,
  psql_orioledb-17,
  pg_regress,
}:
writeShellApplication {
  name = "docker-image-test";
  runtimeInputs = [
    coreutils
    gnused
    python3
  ];
  text = ''
    # Test a PostgreSQL Docker image against the pg_regress test suite
    #
    # Usage:
    #   nix run .#docker-image-test -- Dockerfile-17
    #   nix run .#docker-image-test -- --no-build Dockerfile-15

    set -euo pipefail

    # Find repo root (where Dockerfiles live)
    REPO_ROOT="$(pwd)"
    TESTS_DIR="$REPO_ROOT/nix/tests"
    TESTS_SQL_DIR="$TESTS_DIR/sql"
    HTTP_MOCK_SERVER="$TESTS_DIR/http-mock-server.py"
    CONTAINER_NAME=""
    IMAGE_TAG=""
    POSTGRES_USER="supabase_admin"
    POSTGRES_DB="postgres"
    POSTGRES_PASSWORD="postgres"
    OUTPUT_DIR=""
    HTTP_MOCK_PORT=""
    HTTP_MOCK_PID=""
    KEEP_CONTAINER=false

    # Colors for output
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    NC='\033[0m'

    log_info() { echo -e "''${GREEN}[INFO]''${NC} $1"; }
    log_warn() { echo -e "''${YELLOW}[WARN]''${NC} $1"; }
    log_error() { echo -e "''${RED}[ERROR]''${NC} $1"; }

    print_help() {
        cat << 'EOF'
    Usage: nix run .#docker-image-test -- [OPTIONS] DOCKERFILE

    Test a PostgreSQL Docker image against the pg_regress test suite.

    Arguments:
      DOCKERFILE    The Dockerfile to build and test (e.g., Dockerfile-17)

    Options:
      -h, --help    Show this help message
      --no-build    Skip building the image (use existing)
      --keep        Keep the container running after tests (for debugging)

    Examples:
      nix run .#docker-image-test -- Dockerfile-17
      nix run .#docker-image-test -- Dockerfile-15
      nix run .#docker-image-test -- Dockerfile-orioledb-17
      nix run .#docker-image-test -- --no-build Dockerfile-17
    EOF
    }

    get_version_info() {
        local dockerfile="$1"
        case "$dockerfile" in
            Dockerfile-15) echo "15 5436" ;;
            Dockerfile-17) echo "17 5435" ;;
            Dockerfile-orioledb-17) echo "orioledb-17 5437" ;;
            *)
                log_error "Unknown Dockerfile: $dockerfile"
                log_error "Supported: Dockerfile-15, Dockerfile-17, Dockerfile-orioledb-17"
                exit 1
                ;;
        esac
    }

    # Tests to skip for OrioleDB
    ORIOLEDB_SKIP_TESTS=(
        "index_advisor"
    )

    get_test_list() {
        local version="$1"
        local tests=()

        # Build list of OrioleDB-specific test basenames
        local orioledb_variants=()
        for f in "$TESTS_SQL_DIR"/z_orioledb-17_*.sql; do
            if [[ -f "$f" ]]; then
                local variant_name
                variant_name=$(basename "$f" .sql)
                local base_name="''${variant_name#z_orioledb-17_}"
                orioledb_variants+=("$base_name")
            fi
        done

        for f in "$TESTS_SQL_DIR"/*.sql; do
            local _basename
            _basename=$(basename "$f" .sql)

            if [[ "$version" == "orioledb-17" ]]; then
                local should_skip=false
                for skip_test in "''${ORIOLEDB_SKIP_TESTS[@]}"; do
                    if [[ "$_basename" == "$skip_test" ]]; then
                        should_skip=true
                        break
                    fi
                done
                if [[ "$should_skip" == "true" ]]; then
                    continue
                fi
            fi

            if [[ "$_basename" == z_* ]]; then
                case "$version" in
                    15) [[ "$_basename" == z_15_* ]] && tests+=("$_basename") ;;
                    17) [[ "$_basename" == z_17_* ]] && tests+=("$_basename") ;;
                    orioledb-17) [[ "$_basename" == z_orioledb-17_* ]] && tests+=("$_basename") ;;
                esac
            else
                if [[ "$version" == "orioledb-17" ]]; then
                    local has_variant=false
                    for variant in "''${orioledb_variants[@]}"; do
                        if [[ "$_basename" == "$variant" ]]; then
                            has_variant=true
                            break
                        fi
                    done
                    if [[ "$has_variant" == "false" ]]; then
                        tests+=("$_basename")
                    fi
                else
                    tests+=("$_basename")
                fi
            fi
        done

        printf '%s\n' "''${tests[@]}" | sort
    }

    cleanup() {
        local exit_code=$?

        if [[ -n "$HTTP_MOCK_PID" ]]; then
            kill "$HTTP_MOCK_PID" 2>/dev/null || true
        fi

        if [[ -n "$CONTAINER_NAME" ]] && [[ "$KEEP_CONTAINER" != "true" ]]; then
            log_info "Cleaning up container $CONTAINER_NAME..."
            docker rm -f "$CONTAINER_NAME" 2>/dev/null || true
        fi

        if [[ -n "$OUTPUT_DIR" ]] && [[ -d "$OUTPUT_DIR" ]]; then
            if [[ $exit_code -ne 0 ]]; then
                log_info "Test output preserved at: $OUTPUT_DIR"
            else
                rm -rf "$OUTPUT_DIR"
            fi
        fi

        exit $exit_code
    }

    trap cleanup EXIT

    wait_for_postgres() {
        local host="$1"
        local port="$2"
        local max_attempts=60
        local attempt=1

        log_info "Waiting for PostgreSQL to be ready..."

        while [[ $attempt -le $max_attempts ]]; do
            if "$PG_ISREADY_PATH" -h "$host" -p "$port" -U "$POSTGRES_USER" -q 2>/dev/null; then
                log_info "PostgreSQL is ready"
                return 0
            fi
            sleep 1
            ((attempt++))
        done

        log_error "PostgreSQL failed to start after ''${max_attempts}s"
        return 1
    }

    main() {
        local dockerfile=""
        local skip_build=false

        while [[ $# -gt 0 ]]; do
            case "$1" in
                -h|--help) print_help; exit 0 ;;
                --no-build) skip_build=true; shift ;;
                --keep) KEEP_CONTAINER=true; shift ;;
                -*) log_error "Unknown option: $1"; print_help; exit 1 ;;
                *) dockerfile="$1"; shift ;;
            esac
        done

        if [[ -z "$dockerfile" ]]; then
            log_error "Dockerfile argument required"
            print_help
            exit 1
        fi

        if [[ ! -f "$REPO_ROOT/$dockerfile" ]]; then
            log_error "Dockerfile not found: $REPO_ROOT/$dockerfile"
            exit 1
        fi

        read -r VERSION PORT <<< "$(get_version_info "$dockerfile")"

        IMAGE_TAG="pg-docker-test:''${VERSION}"
        CONTAINER_NAME="pg-test-''${VERSION}-$$"
        OUTPUT_DIR=$(mktemp -d)

        log_info "Testing $dockerfile (version: $VERSION, port: $PORT)"

        if [[ "$skip_build" != "true" ]]; then
            log_info "Building image from $dockerfile..."
            if ! docker build -f "$REPO_ROOT/$dockerfile" -t "$IMAGE_TAG" "$REPO_ROOT"; then
                log_error "Failed to build image"
                exit 1
            fi
        else
            log_info "Skipping build (--no-build)"
            if ! docker image inspect "$IMAGE_TAG" &>/dev/null; then
                log_error "Image $IMAGE_TAG not found. Run without --no-build first."
                exit 1
            fi
        fi

        # Set paths based on version
        case "$VERSION" in
            15)
                PSQL_PATH="${psql_15}/bin/psql"
                PG_ISREADY_PATH="${psql_15}/bin/pg_isready"
                ;;
            17)
                PSQL_PATH="${psql_17}/bin/psql"
                PG_ISREADY_PATH="${psql_17}/bin/pg_isready"
                ;;
            orioledb-17)
                PSQL_PATH="${psql_orioledb-17}/bin/psql"
                PG_ISREADY_PATH="${psql_orioledb-17}/bin/pg_isready"
                ;;
        esac
        PG_REGRESS_PATH="${pg_regress}/bin/pg_regress"

        log_info "Using psql: $PSQL_PATH"
        log_info "Using pg_isready: $PG_ISREADY_PATH"
        log_info "Using pg_regress: $PG_REGRESS_PATH"

        log_info "Starting container $CONTAINER_NAME..."
        docker run -d \
            --name "$CONTAINER_NAME" \
            -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
            -p "$PORT:5432" \
            "$IMAGE_TAG"

        if ! wait_for_postgres "localhost" "$PORT"; then
            log_error "Container logs:"
            docker logs "$CONTAINER_NAME"
            exit 1
        fi

        log_info "Starting HTTP mock server on host..."
        HTTP_MOCK_PORT=8880

        python3 "$HTTP_MOCK_SERVER" $HTTP_MOCK_PORT &
        HTTP_MOCK_PID=$!

        sleep 2
        if ! kill -0 "$HTTP_MOCK_PID" 2>/dev/null; then
            log_error "HTTP mock server failed to start"
            exit 1
        fi
        log_info "HTTP mock server started on host port $HTTP_MOCK_PORT (PID: $HTTP_MOCK_PID)"

        HTTP_MOCK_HOST="host.docker.internal"
        if [[ "$(uname)" == "Linux" ]]; then
            HTTP_MOCK_HOST=$(docker inspect -f '{{range .NetworkSettings.Networks}}{{.Gateway}}{{end}}' "$CONTAINER_NAME")
        fi
        log_info "Container will access mock server at $HTTP_MOCK_HOST:$HTTP_MOCK_PORT"

        log_info "Running prime.sql to enable extensions..."
        if ! PGPASSWORD="$POSTGRES_PASSWORD" "$PSQL_PATH" \
            -h localhost \
            -p "$PORT" \
            -U "$POSTGRES_USER" \
            -d "$POSTGRES_DB" \
            -v ON_ERROR_STOP=1 \
            -X \
            -f "$TESTS_DIR/prime.sql" 2>&1; then
            log_error "Failed to run prime.sql"
            exit 1
        fi

        log_info "Creating test_config table..."
        PGPASSWORD="$POSTGRES_PASSWORD" "$PSQL_PATH" \
            -h localhost \
            -p "$PORT" \
            -U "$POSTGRES_USER" \
            -d "$POSTGRES_DB" \
            -c "CREATE TABLE IF NOT EXISTS test_config (key TEXT PRIMARY KEY, value TEXT);
                INSERT INTO test_config (key, value) VALUES ('http_mock_port', '$HTTP_MOCK_PORT')
                ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;
                INSERT INTO test_config (key, value) VALUES ('http_mock_host', '$HTTP_MOCK_HOST')
                ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;"

        log_info "Collecting tests for version $VERSION..."
        TEST_LIST=()
        while IFS= read -r line; do
            TEST_LIST+=("$line")
        done < <(get_test_list "$VERSION")
        log_info "Running ''${#TEST_LIST[@]} tests"

        mkdir -p "$OUTPUT_DIR/regression_output"

        log_info "Preparing test files..."
        PATCHED_TESTS_DIR="$OUTPUT_DIR/tests"
        cp -r "$TESTS_DIR" "$PATCHED_TESTS_DIR"

        for f in pgmq.out vault.out; do
            if [[ -f "$PATCHED_TESTS_DIR/expected/$f" ]]; then
                # shellcheck disable=SC2016
                sed -i.bak \
                    -e 's/ "\$user"/ "\\$user"/g' \
                    -e 's/search_path            $/search_path             /' \
                    -e 's/^-----------------------------------$/------------------------------------/' \
                    "$PATCHED_TESTS_DIR/expected/$f"
                rm -f "$PATCHED_TESTS_DIR/expected/$f.bak"
            fi
        done
        if [[ -f "$PATCHED_TESTS_DIR/expected/roles.out" ]]; then
            # shellcheck disable=SC2016
            sed -i.bak \
                -e 's/\\"\$user\\"/\\"\\\\$user\\"/g' \
                "$PATCHED_TESTS_DIR/expected/roles.out"
            rm -f "$PATCHED_TESTS_DIR/expected/roles.out.bak"
        fi

        # Patch http.sql and http.out to use http_mock_host instead of localhost
        # This is needed because localhost inside container doesn't reach host's mock server
        if [[ -f "$PATCHED_TESTS_DIR/sql/http.sql" ]]; then
            sed -i.bak \
                -e "s@'http://localhost:'@'http://' || (SELECT value FROM test_config WHERE key = 'http_mock_host') || ':'@g" \
                "$PATCHED_TESTS_DIR/sql/http.sql"
            rm -f "$PATCHED_TESTS_DIR/sql/http.sql.bak"
        fi
        if [[ -f "$PATCHED_TESTS_DIR/expected/http.out" ]]; then
            sed -i.bak \
                -e "s@'http://localhost:'@'http://' || (SELECT value FROM test_config WHERE key = 'http_mock_host') || ':'@g" \
                "$PATCHED_TESTS_DIR/expected/http.out"
            rm -f "$PATCHED_TESTS_DIR/expected/http.out.bak"
        fi

        log_info "Running pg_regress..."
        local regress_exit=0

        if ! PGPASSWORD="$POSTGRES_PASSWORD" "$PG_REGRESS_PATH" \
            --use-existing \
            --dbname="$POSTGRES_DB" \
            --inputdir="$PATCHED_TESTS_DIR" \
            --outputdir="$OUTPUT_DIR/regression_output" \
            --host=localhost \
            --port="$PORT" \
            --user="$POSTGRES_USER" \
            "''${TEST_LIST[@]}" 2>&1; then
            regress_exit=1
        fi

        if [[ $regress_exit -eq 0 ]]; then
            log_info "''${GREEN}PASS: all ''${#TEST_LIST[@]} tests passed''${NC}"
        else
            log_error "FAIL: some tests failed"
            if [[ -f "$OUTPUT_DIR/regression_output/regression.diffs" ]]; then
                echo ""
                echo "=== regression.diffs ==="
                cat "$OUTPUT_DIR/regression_output/regression.diffs"
                echo "========================"
            fi
            exit 1
        fi

        if [[ "$KEEP_CONTAINER" == "true" ]]; then
            log_info "Container kept running: $CONTAINER_NAME (port $PORT)"
            log_info "Connect with: psql -h localhost -p $PORT -U $POSTGRES_USER $POSTGRES_DB"
        fi
    }

    main "$@"
  '';
}
