#!/usr/bin/env bash
# shellcheck shell=bash
#
# Populate DEST with the nix closures of psql_<major>/bin for every supported
# major version (currently 15 and 17), as a nix chroot store, plus the scripts
# needed to mount and use it.
#
# DEST is meant to become an EBS volume
# See .github/workflows/pg-binaries-snapshot.yml for the
# snapshot build.
#
# Usage:
#   scripts/build-pg-binaries-store.sh /mnt/pgbin
#   VERSIONS="15 17" scripts/build-pg-binaries-store.sh /mnt/pgbin

set -o errexit
set -o nounset
set -o pipefail

REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
DEST=${1:?usage: $0 DEST}

log() { echo "[$(date -u +%H:%M:%S)] $*" >&2; }

# Majors we ship binaries for. orioledb builds are excluded: they are not a
# pg_upgrade target for the standard flavour.
supported_majors() {
	if [ -n "${VERSIONS:-}" ]; then
		echo "$VERSIONS"
		return
	fi
	nix run nixpkgs#yq-go -- '.postgres_major[]' "$REPO_DIR/ansible/vars.yml" | grep -E '^[0-9]+$'
}

SYSTEM=$(nix eval --impure --raw --expr 'builtins.currentSystem')
GIT_SHA=$(git -C "$REPO_DIR" rev-parse HEAD)
MAJORS=$(supported_majors | tr '\n' ' ' | sed 's/ *$//')
log "dest=$DEST system=$SYSTEM majors=$MAJORS"

# Realise the closures into DEST's own chroot store, i.e. DEST/nix/store/<hash>-...,
# which is what lets the target overlay it onto its own /nix/store: the absolute
# store paths the binaries were linked against resolve unchanged.
#
# `--store DEST` means paths are substituted (or built) directly into that store
# and the host /nix/store is never read. So the content is defined by the flake
# plus the binary cache, not by whatever the builder happens to have lying around
# - a mutated or half-written host store path cannot leak in. Costs a download of
# the whole closure per run.
BINS=()
for major in $MAJORS; do
	log "Realising psql_$major into $DEST"
	out=$(nix build --eval-store auto --store "$DEST" --no-link --print-out-paths \
		"$REPO_DIR#psql_${major}/bin")
	BINS+=("$major $out/bin")
done

printf '%s\n' "${BINS[@]}" >"$DEST/bins.txt"
# Values are quoted so this stays safe to `source`.
{
	echo "git_sha=\"$GIT_SHA\""
	echo "system=\"$SYSTEM\""
	echo "majors=\"$MAJORS\""
} >"$DEST/manifest.txt"

cat >"$DEST/mount-store.sh" <<'EOF'
#!/usr/bin/env bash
# Run as root on the target instance, after mounting this volume (read-only is
# fine). Overlays this volume's store onto the host /nix/store, so the binaries
# execute in place - their ELF interpreter, RPATHs and share/ lookups are all
# absolute /nix/store paths and resolve unchanged.
#
# upperdir is the host store itself, so /nix/store stays writable and anything
# nix writes still lands in the real store; the volume is only a lower layer.
# Host paths win on conflict (identical store hash means identical content).
# umount-store.sh reverses it, taking the volume's paths away again.
set -o errexit -o nounset -o pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
WORKDIR=${WORKDIR:-/nix/.pg-binaries-work}
[ "$(id -u)" = "0" ] || {
	echo "must run as root" >&2
	exit 1
}

if ! findmnt --noheadings --types overlay /nix/store >/dev/null; then
	# workdir must be on the same filesystem as upperdir, and outside of it so
	# nix gc never sees it.
	mkdir -p "$WORKDIR"
	mount -t overlay pg-binaries \
		-o "lowerdir=$HERE/nix/store,upperdir=/nix/store,workdir=$WORKDIR" \
		/nix/store
fi

# Check: the binaries must actually run now, otherwise the overlay is wrong.
while read -r major bin; do
	"$bin/postgres" --version >/dev/null
	"$bin/pg_upgrade" --version >/dev/null
	echo "$major $bin"
done <"$HERE/bins.txt"
EOF

cat >"$DEST/umount-store.sh" <<'EOF'
#!/usr/bin/env bash
# Undo mount-store.sh. Store paths nix wrote while the overlay was up were
# written to the real /nix/store and survive.
set -o errexit -o nounset -o pipefail
WORKDIR=${WORKDIR:-/nix/.pg-binaries-work}
umount /nix/store
rm -rf "$WORKDIR"
EOF
chmod +x "$DEST/mount-store.sh" "$DEST/umount-store.sh"

log "Populated $DEST"
