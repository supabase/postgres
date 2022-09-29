#! /usr/bin/env bash

set -euo pipefail

MODE=$1
psql -h localhost -U supabase_admin -d postgres -c "ALTER SYSTEM SET default_transaction_read_only to ${MODE};"
psql -h localhost -U supabase_admin -d postgres -c "SELECT pg_reload_conf();"
