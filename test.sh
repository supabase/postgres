# Check if different PostgreSQL versions use different Rust compilers

echo "🔍 Checking Rust compiler versions for different PostgreSQL builds..."

echo "=== PostgreSQL 15 Rust toolchain ==="
nix eval .#psql_15/exts/pgvectorscale.nativeBuildInputs --json | jq -r '.[]' | grep -i rust

echo ""
echo "=== PostgreSQL 17 Rust toolchain ==="
nix eval .#psql_17/exts/pgvectorscale.nativeBuildInputs --json | jq -r '.[]' | grep -i rust

echo ""
echo "=== Let's see if they have different Rust versions ==="
echo "PostgreSQL 15 detailed inputs:"
nix eval .#psql_15/exts/pgvectorscale.nativeBuildInputs --json | jq -r '.[]' | head -5

echo ""
echo "PostgreSQL 17 detailed inputs:"
nix eval .#psql_17/exts/pgvectorscale.nativeBuildInputs --json | jq -r '.[]' | head -5

echo ""
echo "🔍 Check if there are different Rust versions in the paths..."
echo "PostgreSQL 15 Rust version:"
nix eval .#psql_15/exts/pgvectorscale.nativeBuildInputs --json | jq -r '.[]' | grep rust | head -1 | grep -o '1\.[0-9]\+\.[0-9]\+'

echo ""
echo "PostgreSQL 17 Rust version:"
nix eval .#psql_17/exts/pgvectorscale.nativeBuildInputs --json | jq -r '.[]' | grep rust | head -1 | grep -o '1\.[0-9]\+\.[0-9]\+'

echo ""
echo "💡 THEORY: The issue might be:"
echo "1. Different PostgreSQL versions expect different pgrx API signatures"
echo "2. pgrx 0.12.9 compiled against PostgreSQL 17 headers vs PostgreSQL 15 headers"
echo "3. PostgreSQL 17 changed some internal APIs that pgrx interfaces with"

echo ""
echo "🔧 Let's check PostgreSQL version-specific pgrx builds:"
echo "Check if pgrx is built differently for each PostgreSQL version:"

echo "PostgreSQL 15 pgrx path:"
nix eval .#psql_15/exts/pgvectorscale.nativeBuildInputs --json | jq -r '.[]' | grep pgrx

echo ""
echo "PostgreSQL 17 pgrx path:"
nix eval .#psql_17/exts/pgvectorscale.nativeBuildInputs --json | jq -r '.[]' | grep pgrx

echo ""
echo "🎯 LIKELY SOLUTION: Use PostgreSQL 15 which we know works!"
echo "Let's manually start PostgreSQL 15:"

cat << 'EOF'
PG_PATH=$(nix build .#postgresql_15 --no-link --print-out-paths)
export PATH="$PG_PATH/bin:$PATH"
initdb -D /tmp/pg15-working
postgres -D /tmp/pg15-working -p 5432 &
sleep 3
createdb vectortest
psql vectortest -c "CREATE EXTENSION vectorscale CASCADE;"
psql vectortest -c "SELECT extname, extversion FROM pg_extension;"
EOF