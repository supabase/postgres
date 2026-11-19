#!/usr/bin/env bash
set -euo pipefail

# Takes the files a PR changed and refreshes the hashes or checksums in them.
# Run it from the repo root, for example: nix run .#rehash -- nix/pgbouncer.nix
# The renovate-rehash workflow runs it on Renovate PRs.
#
# A changed .nix file is a package definition by default.
# The file name gives the package name: nix/packages/pg-backrest.nix is the package pg-backrest.
# We run nix-update on that package, and skip the file if there is no such package.
# The table at the bottom lists the files that need something else.
# The first word of an entry is the command and the rest are its arguments.
# A file that is neither in the table nor a .nix file is ignored.

# Refreshes the source hash of each flake attribute and keeps its version.
# @system@ in an attribute is replaced with the current system, like x86_64-linux.
nix_update() {
	local attr system
	system=$(nix eval --raw --impure --expr builtins.currentSystem)
	for attr in "$@"; do
		nix-update --flake --version=skip "${attr//@system@/$system}"
	done
}

# Refreshes the source hash of the package named like the file $1, if there is one.
nix_update_by_file_name() {
	local name
	name=$(basename "$1" .nix)
	if ! nix eval --raw ".#$name.name" >/dev/null 2>&1; then
		echo "Skipping $1: there is no package named $name." >&2
		return 0
	fi
	nix_update "$name"
}

# Refreshes the hashes of the tzdata and tzcode tarballs in nix/nixpkgs.nix.
# It reads the version from the overlay and writes each hash on the line after its URL.
rehash_tzdata() {
	local version kind sri
	version=$(sed -En 's/^ *version = "([^"]*)";.*/\1/p' nix/nixpkgs.nix | head -n 1)
	for kind in tzdata tzcode; do
		sri=$(nix-hash --to-sri --type sha256 "$(nix-prefetch-url --type sha256 "https://data.iana.org/time-zones/releases/$kind$version.tar.gz")")
		echo "$kind$version -> $sri" >&2
		sed -Ei "/releases\/$kind\\\$\{version\}/{n;s|sha256-[^\"]*|$sri|}" nix/nixpkgs.nix
	done
}

# Refreshes the checksums in ansible/vars.yml for each *_release line the PR changed.
# BASE_REF is the PR's base branch.
rehash_ansible_artifacts() {
	local changed name version
	changed=$(git diff -U0 "origin/${BASE_REF:?}...HEAD" -- ansible/vars.yml | sed -En 's/^\+([a-z_]*)_release: *"?([^" #]*).*/\1 \2/p')
	while read -r name version; do
		[[ -n $name ]] || continue
		echo "$name $version" >&2
		nix run .#update-ansible-artifacts -- "$name" "$version"
	done <<<"$changed"
}

# Renovate changes the commit that flake.nix pins for the multigres input.
# `nix flake lock` brings flake.lock in line, and only touches the inputs that changed.
# Then we refresh pgctld's vendorHash, since multigres is pgctld's source.
rehash_multigres() {
	nix flake lock
	nix_update_by_file_name nix/packages/pgctld.nix
}

if false; then
	# just here to quiet down some not-so-smart editor tooling
	false
	rehash_ansible_artifacts
	rehash_tzdata
	rehash_multigres
	nix_update_by_file_name non-existent
	exit 1
fi

# Files whose name does not give the package, or that need a different command.
declare -A table=(
	['ansible/vars.yml']=rehash_ansible_artifacts
	['flake.nix']=rehash_multigres
	['nix/ext/pgroonga/groonga.nix']='nix_update supabase-groonga'
	['nix/ext/supautils.nix']='nix_update legacyPackages.@system@.psql_17.exts.supautils'
	['nix/nixpkgs.nix']=rehash_tzdata
	['nix/packages/supascan.nix']='nix_update supascan goss'
	['nix/packages/wal-g.nix']='nix_update wal-g-2 wal-g-3'
)

for file in "$@"; do
	if [[ -n ${table[$file]:-} ]]; then
		read -ra command <<<"${table[$file]}"
	elif [[ $file == *.nix ]]; then
		command=(nix_update_by_file_name "$file")
	else
		continue
	fi

	[[ ${GITHUB_ACTIONS:-} == true ]] && echo "::group::$file"

	"${command[@]}"

	[[ ${GITHUB_ACTIONS:-} == true ]] && echo "::endgroup::"

done

exit 0 # so we don't return !0 when not running under GHA last iter
