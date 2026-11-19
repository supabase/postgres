#!/usr/bin/env bash
set -euo pipefail

# Takes the files a PR changed and refreshes the hashes or checksums in them.
# Run it from the repo root, for example: BASE_REF=develop nix run .#rehash -- ansible/vars.yml
# The renovate-rehash workflow runs it on Renovate PRs.
#
# The table at the bottom maps a file to the command to run for it.
# The first word of an entry is the command and the rest are its arguments.
# A file that is not in the table is ignored.

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

if false; then
	# just here to quiet down some not-so-smart editor tooling
	false
	rehash_ansible_artifacts
	rehash_tzdata
	exit 1
fi

declare -A table=(
	['ansible/vars.yml']=rehash_ansible_artifacts
	['nix/nixpkgs.nix']=rehash_tzdata
)

for file in "$@"; do
	[[ -n ${table[$file]:-} ]] || continue
	read -ra command <<<"${table[$file]}"

	[[ ${GITHUB_ACTIONS:-} == true ]] && echo "::group::$file"

	"${command[@]}"

	[[ ${GITHUB_ACTIONS:-} == true ]] && echo "::endgroup::"

done

exit 0 # so we don't return !0 when not running under GHA last iter
