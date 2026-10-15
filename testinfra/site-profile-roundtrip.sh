#!/usr/bin/env bash
# Usage: site-profile-roundtrip <site_env_path> <out_dir>
# Run as root on a host booted from the latest AMI.
set -euo pipefail

SITE_ENV="${1:?Usage: $0 <site_env_path> <out_dir>}"
OUT="${2:?Usage: $0 <site_env_path> <out_dir>}"
PROFILE=/nix/var/nix/profiles/site
SANITY="${SITE_PROFILE_SANITY:-site-profile-sanity}"

mkdir -p "$OUT"
export MANIFEST_EXCLUDES="--exclude=./nix/store --exclude=./nix/.ro-store --exclude=./nix/.rw-store --exclude=./nix/var/nix/db"

# Store paths, the nix db, and generation links change on every update by design.
# Sysctl is dropped as it holds live counters. The store is skipped at capture, as hashing it dominates the runtime.
snapshot() {
	manifest-snapshot | sed '/^--- sysctl ---$/,$d' | grep -v -e '^\./nix/store' -e '^\./nix/var/nix/db' -e '^\./nix/var/nix/profiles/.*-[0-9]*-link' -e '^\./nix/var/nix/gcroots/auto/' -e '^\./nix/var/nix/temproots' >"$OUT/$1.txt"
}

update() {
	nix-env --profile "$PROFILE" --set "$SITE_ENV"
	"$PROFILE/bin/activate"
}

expect_same() {
	if ! diff -u "$OUT/$1.txt" "$OUT/$2.txt" >"$OUT/$1-vs-$2.diff"; then
		echo "FAIL: $1 and $2 differ"
		cat "$OUT/$1-vs-$2.diff"
		exit 1
	fi
	echo "ok: $1 == $2"
}

snapshot m0

update
snapshot m1
diff -u "$OUT/m0.txt" "$OUT/m1.txt" >"$OUT/update.diff" || true
"$SANITY" updated

update
snapshot m2
expect_same m1 m2

if [[ -x "$PROFILE/bin/deactivate" ]]; then
	"$PROFILE/bin/deactivate"
fi
nix-env --profile "$PROFILE" --rollback
snapshot m3
expect_same m0 m3
"$SANITY" rolled-back
