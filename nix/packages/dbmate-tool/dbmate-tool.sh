#!/usr/bin/env bash

set -euo pipefail

declare -A all=(["15"]=1 ["17"]=1 ["orioledb-17"]=1)
declare versions=()
flake_url=.

print_help() {
	cat <<-EOF
		Usage: nix run .#dbmate-tool -- [options]

		Options:
		  -v, --version [15|17|orioledb-17|all]  PostgreSQL version to regenerate the schema for (default: all)
		  -f, --flake-url URL                    Flake to build the schema from (default: .)
		  -h, --help                             Show this help message

		Description:
		  Builds schema-dump-<version>, which runs the init scripts and migrations with dbmate against a
		  throwaway Postgres and dumps the schema, then copies the dump to migrations/schema-<version>.sql.
		  CI checks that file against the same package. Run it from the root of the repository.
		  NOTE: To create a migration, you must run 'nix develop' and then 'dbmate new <migration_name>'
		  to create a new migration file.

		Examples:
		  nix run .#dbmate-tool
		  nix run .#dbmate-tool -- --version 15
		  nix run .#dbmate-tool -- --version 17 --flake-url github:supabase/postgres/<commithash>
	EOF
}

while (($# > 0)); do
	case $1 in
	-v | --version)
		if [[ -z ${2:-} || $2 == -* ]]; then
			echo "Error: --version requires an argument ($(printf '%s\n' "${!all[@]}" | sort | paste -sd ' ') all)" >&2
			exit 1
		fi

		if [[ $2 == all ]]; then
			versions=("${!all[@]}")
		elif [[ -v all[$2] ]]; then
			versions+=("$2")
		else
			echo "Error: unknown version $2, expected one of $(printf '%s\n' "${!all[@]}" | sort | paste -sd ' ') all" >&2
			exit 1
		fi
		;;
	-f | --flake-url)
		if [[ -z ${2:-} || $2 == -* ]]; then
			echo "Error: --flake-url requires an argument" >&2
			exit 1
		fi
		flake_url=$2
		;;
	-h | --help) print_help && exit 0 ;;
	*) echo "Unknown option: $1" >&2 && print_help >&2 && exit 1 ;;
	esac
	shift 2
done

if [[ ! -d migrations ]]; then
	echo "Error: migrations/ not found, run this from the root of the repository" >&2
	exit 1
fi

# no --version means every version
if ((${#versions[@]} == 0)); then
	versions=("${!all[@]}")
fi

installables=()
for v in $(printf '%s\n' "${versions[@]}" | sort -u); do
	installables+=("$flake_url#schema-dump-$v")
done

echo "Building ${installables[*]}"
dumps=$(nix build "${installables[@]}" --no-link --print-out-paths)
for dump in $dumps; do
	# the store path ends in schema-dump-<version>
	v=${dump##*-schema-dump-}
	# cat, not cp: the store copy is read-only and cp would carry that mode into the repo
	cat "$dump/schema.sql" >"migrations/schema-$v.sql"
	echo "Wrote migrations/schema-$v.sql"
done
