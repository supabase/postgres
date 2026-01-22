#!/usr/bin/env bash
# Test a PostgreSQL Docker image against the pg_regress test suite
#
# Usage:
#   ./test-docker-image.sh Dockerfile-17
#   ./test-docker-image.sh Dockerfile-15
#   ./test-docker-image.sh Dockerfile-orioledb-17
#
# Dependencies:
#   - Docker
#   - Nix (for psql and pg_regress)

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TESTS_DIR="$SCRIPT_DIR/nix/tests"
TESTS_SQL_DIR="$TESTS_DIR/sql"
HTTP_MOCK_SERVER="$TESTS_DIR/http-mock-server.py"
CONTAINER_NAME=""
IMAGE_TAG=""
POSTGRES_USER="supabase_admin"
POSTGRES_DB="postgres"
POSTGRES_PASSWORD="postgres"
OUTPUT_DIR=""
HTTP_MOCK_PORT=""

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_help() {
    cat << 'EOF'
Usage: ./test-docker-image.sh [OPTIONS] DOCKERFILE

Test a PostgreSQL Docker image against the pg_regress test suite.

Arguments:
  DOCKERFILE    The Dockerfile to build and test (e.g., Dockerfile-17)

Options:
  -h, --help    Show this help message
  --no-build    Skip building the image (use existing)
  --keep        Keep the container running after tests (for debugging)

Examples:
  ./test-docker-image.sh Dockerfile-17
  ./test-docker-image.sh Dockerfile-15
  ./test-docker-image.sh Dockerfile-orioledb-17
  ./test-docker-image.sh --no-build Dockerfile-17
EOF
}

# Map Dockerfile to version info
get_version_info() {
    local dockerfile="$1"
    case "$dockerfile" in
        Dockerfile-15)
            echo "15 5436"
            ;;
        Dockerfile-17)
            echo "17 5435"
            ;;
        Dockerfile-orioledb-17)
            echo "orioledb-17 5437"
            ;;
        *)
            log_error "Unknown Dockerfile: $dockerfile"
            log_error "Supported: Dockerfile-15, Dockerfile-17, Dockerfile-orioledb-17"
            exit 1
            ;;
    esac
}

# Tests to skip for OrioleDB (not compatible with OrioleDB storage)
ORIOLEDB_SKIP_TESTS=(
    "index_advisor"  # index_advisor doesn't support OrioleDB tables
)

# Filter test files based on version
get_test_list() {
    local version="$1"
    local tests=()

    # Build list of OrioleDB-specific test basenames (tests that have z_orioledb-17_ variants)
    local orioledb_variants=()
    for f in "$TESTS_SQL_DIR"/z_orioledb-17_*.sql; do
        if [[ -f "$f" ]]; then
            local variant_name
            variant_name=$(basename "$f" .sql)
            # Extract the base test name (remove z_orioledb-17_ prefix)
            local base_name="${variant_name#z_orioledb-17_}"
            orioledb_variants+=("$base_name")
        fi
    done

    for f in "$TESTS_SQL_DIR"/*.sql; do
        local _basename
        _basename=$(basename "$f" .sql)

        # Skip tests that don't work with OrioleDB
        if [[ "$version" == "orioledb-17" ]]; then
            local should_skip=false
            for skip_test in "${ORIOLEDB_SKIP_TESTS[@]}"; do
                if [[ "$_basename" == "$skip_test" ]]; then
                    should_skip=true
                    break
                fi
            done
            if [[ "$should_skip" == "true" ]]; then
                continue
            fi
        fi

        # Check if it's a version-specific test (starts with z_)
        if [[ "$_basename" == z_* ]]; then
            # Only include if it matches our version
            case "$version" in
                15)
                    [[ "$_basename" == z_15_* ]] && tests+=("$_basename")
                    ;;
                17)
                    [[ "$_basename" == z_17_* ]] && tests+=("$_basename")
                    ;;
                orioledb-17)
                    [[ "$_basename" == z_orioledb-17_* ]] && tests+=("$_basename")
                    ;;
            esac
        else
            # Non-version-specific tests: check if OrioleDB variant exists
            if [[ "$version" == "orioledb-17" ]]; then
                # Skip common test if OrioleDB-specific variant exists
                local has_variant=false
                for variant in "${orioledb_variants[@]}"; do
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

    # Sort the tests
    printf '%s\n' "${tests[@]}" | sort
}

# Cleanup function
cleanup() {
    # since this function is set as the trap for EXIT
    # store the return code of the last command that 
    # was executed before said EXIT
    local exit_code=$?

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

# Wait for postgres to be ready
wait_for_postgres() {
    local host="$1"
    local port="$2"
    local max_attempts=60
    local attempt=1

    log_info "Waiting for PostgreSQL to be ready..."

    while [[ $attempt -le $max_attempts ]]; do
        if pg_isready -h "$host" -p "$port" -U "$POSTGRES_USER" -q 2>/dev/null; then
            log_info "PostgreSQL is ready"
            return 0
        fi
        sleep 1
        ((attempt++))
    done

    log_error "PostgreSQL failed to start after ${max_attempts}s"
    return 1
}

# Main
main() {
    local dockerfile=""
    local skip_build=false
    KEEP_CONTAINER=false

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                print_help
                exit 0
                ;;
            --no-build)
                skip_build=true
                shift
                ;;
            --keep)
                KEEP_CONTAINER=true
                shift
                ;;
            -*)
                log_error "Unknown option: $1"
                print_help
                exit 1
                ;;
            *)
                dockerfile="$1"
                shift
                ;;
        esac
    done

    if [[ -z "$dockerfile" ]]; then
        log_error "Dockerfile argument required"
        print_help
        exit 1
    fi

    # Check dockerfile exists
    if [[ ! -f "$SCRIPT_DIR/$dockerfile" ]]; then
        log_error "Dockerfile not found: $SCRIPT_DIR/$dockerfile"
        exit 1
    fi

    # Get version info
    read -r VERSION PORT <<< "$(get_version_info "$dockerfile")"

    IMAGE_TAG="pg-docker-test:${VERSION}"
    CONTAINER_NAME="pg-test-${VERSION}-$$"
    OUTPUT_DIR=$(mktemp -d)

    log_info "Testing $dockerfile (version: $VERSION, port: $PORT)"

    # Build image
    if [[ "$skip_build" != "true" ]]; then
        log_info "Building image from $dockerfile..."
        if ! docker build -f "$SCRIPT_DIR/$dockerfile" -t "$IMAGE_TAG" "$SCRIPT_DIR"; then
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

    # Start container
    log_info "Starting container $CONTAINER_NAME..."
    docker run -d \
        --name "$CONTAINER_NAME" \
        -e POSTGRES_PASSWORD="$POSTGRES_PASSWORD" \
        -p "$PORT:5432" \
        "$IMAGE_TAG"

    # Wait for postgres
    if ! wait_for_postgres "localhost" "$PORT"; then
        log_error "Container logs:"
        docker logs "$CONTAINER_NAME"
        exit 1
    fi

    # Get psql and pg_regress from Nix
    log_info "Setting up Nix environment..."

    # Determine psql binary path based on version
    local nix_psql_attr
    case "$VERSION" in
        15) nix_psql_attr="psql_15/bin" ;;
        17) nix_psql_attr="psql_17/bin" ;;
        orioledb-17) nix_psql_attr="psql_orioledb-17/bin" ;;
    esac

    # Build the required Nix packages
    PSQL_PATH=$(nix build --no-link --print-out-paths ".#${nix_psql_attr}")/bin/psql
    PG_REGRESS_PATH=$(nix build --no-link --print-out-paths ".#pg_regress")/bin/pg_regress

    if [[ ! -x "$PSQL_PATH" ]]; then
        log_error "Failed to get psql from Nix"
        exit 1
    fi

    if [[ ! -x "$PG_REGRESS_PATH" ]]; then
        log_error "Failed to get pg_regress from Nix"
        exit 1
    fi

    log_info "Using psql: $PSQL_PATH"
    log_info "Using pg_regress: $PG_REGRESS_PATH"

    # Start HTTP mock server inside the container
    log_info "Starting HTTP mock server inside container..."

    # Copy mock server script into container
    docker cp "$HTTP_MOCK_SERVER" "$CONTAINER_NAME:/tmp/http-mock-server.py"

    # Start mock server in container background
    HTTP_MOCK_PORT=8880
    docker exec -d "$CONTAINER_NAME" python3 /tmp/http-mock-server.py $HTTP_MOCK_PORT

    # Wait for mock server to be ready
    sleep 2
    log_info "HTTP mock server started on port $HTTP_MOCK_PORT (inside container)"

    # Run prime.sql to enable extensions
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

    # Create test_config table with HTTP mock port
    log_info "Creating test_config table..."
    PGPASSWORD="$POSTGRES_PASSWORD" "$PSQL_PATH" \
        -h localhost \
        -p "$PORT" \
        -U "$POSTGRES_USER" \
        -d "$POSTGRES_DB" \
        -c "CREATE TABLE IF NOT EXISTS test_config (key TEXT PRIMARY KEY, value TEXT);
            INSERT INTO test_config (key, value) VALUES ('http_mock_port', '$HTTP_MOCK_PORT')
            ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;"

    # Get filtered test list
    log_info "Collecting tests for version $VERSION..."
    TEST_LIST=()
    while IFS= read -r line; do
        TEST_LIST+=("$line")
    done < <(get_test_list "$VERSION")
    log_info "Running ${#TEST_LIST[@]} tests"

    # Create output directory structure
    mkdir -p "$OUTPUT_DIR/regression_output"

    # Copy tests to temp dir and patch expected files for Docker escaping differences
    log_info "Preparing test files..."
    PATCHED_TESTS_DIR="$OUTPUT_DIR/tests"
    cp -r "$TESTS_DIR" "$PATCHED_TESTS_DIR"

    # Patch expected files: Docker escapes $user as \$user in search_path
    # Only patch files that have the $user escaping difference
    for f in pgmq.out vault.out; do
        if [[ -f "$PATCHED_TESTS_DIR/expected/$f" ]]; then
            sed -i.bak \
                -e 's/ "\$user"/ "\\$user"/g' \
                -e 's/search_path            $/search_path             /' \
                -e 's/^-----------------------------------$/------------------------------------/' \
                "$PATCHED_TESTS_DIR/expected/$f"
            rm -f "$PATCHED_TESTS_DIR/expected/$f.bak"
        fi
    done
    # Patch roles.out separately (different escaping pattern in JSON)
    if [[ -f "$PATCHED_TESTS_DIR/expected/roles.out" ]]; then
        sed -i.bak \
            -e 's/\\"\$user\\"/\\"\\\\$user\\"/g' \
            "$PATCHED_TESTS_DIR/expected/roles.out"
        rm -f "$PATCHED_TESTS_DIR/expected/roles.out.bak"
    fi

    # Run pg_regress
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
        "${TEST_LIST[@]}" 2>&1; then
        regress_exit=1
    fi

    # Report results
    if [[ $regress_exit -eq 0 ]]; then
        log_info "${GREEN}PASS: all ${#TEST_LIST[@]} tests passed${NC}"
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
