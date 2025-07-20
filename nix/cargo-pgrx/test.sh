#!/bin/bash

CLEAN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
  case $1 in
    --clean)
      CLEAN=true
      shift
      ;;
    --verbose)
      VERBOSE=true
      shift
      ;;
    *)
      echo "Unknown option $1"
      exit 1
      ;;
  esac
done

echo -e "\033[32mTesting pgrx-only build in Nix...\033[0m"

if [ "$CLEAN" = true ]; then
    echo -e "\033[33mCleaning previous builds...\033[0m"
    nix-collect-garbage -d
    rm -rf target result
fi

echo -e "\033[34mBuilding pgrx components only...\033[0m"

# Updated to properly call the function with nixpkgs
nix-build -E 'with import <nixpkgs> {}; callPackage ./pgrx.nix {}' --show-trace -v


BUILD_EXIT_CODE=$?

if [ $BUILD_EXIT_CODE -eq 0 ]; then
    echo -e "\033[32m✅ pgrx build successful!\033[0m"
    
    # Test the built cargo-pgrx binary
    echo -e "\033[34mTesting cargo-pgrx binary...\033[0m"
    PGRX_BINARY="$(readlink -f result)/bin/cargo-pgrx"
    
    if [ -f "$PGRX_BINARY" ]; then
        echo "Testing cargo-pgrx version:"
        "$PGRX_BINARY" --version
        
        echo "Testing cargo-pgrx help:"
        "$PGRX_BINARY" pgrx --help | head -10
        
        # Check if vendor directory was included (if you implement that solution)
        if [ -d "$(readlink -f result)/share/cargo-pgrx" ]; then
            echo -e "\033[32m✅ Vendor directory found in output!\033[0m"
            ls -la "$(readlink -f result)/share/cargo-pgrx/"
        else
            echo -e "\033[33m⚠️  No vendor directory in output (not implemented yet)\033[0m"
        fi
    else
        echo -e "\033[31m❌ cargo-pgrx binary not found in result!\033[0m"
        exit 1
    fi
    
    echo -e "\033[34mTesting basic PostgreSQL functionality...\033[0m"
    nix-shell -p postgresql_15 --run "
        export TMPDIR=/tmp/pgrx-test-\$$
        mkdir -p \$TMPDIR
        initdb -D \$TMPDIR/testdb --no-locale --encoding=UTF8
        postgres -D \$TMPDIR/testdb -p 5433 -F &
        PG_PID=\$!
        sleep 3
        echo 'PostgreSQL started on PID '\$PG_PID
        createdb -p 5433 testdb
        psql -p 5433 -d testdb -c 'SELECT version();' | head -5
        kill \$PG_PID
        wait \$PG_PID 2>/dev/null || true
        rm -rf \$TMPDIR
        echo 'PostgreSQL test completed'
    "
else
    echo -e "\033[31m❌ pgrx build failed!\033[0m"
    echo "Check the error output above for details"
    exit 1
fi

echo -e "\033[32mpgrx-only test completed successfully!\033[0m"
echo -e "\033[34mNext step: Test building an actual extension with buildPgrxExtension\033[0m"