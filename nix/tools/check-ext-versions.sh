#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

versions_file="nix/ext/versions.json"
changed=0

for ext in $(jq -r 'keys[]' "$versions_file"); do
  nixfile="nix/ext/$ext.nix"
  [ -f "$nixfile" ] || nixfile="nix/ext/$ext/default.nix"
  [ -f "$nixfile" ] || continue

  jq -e --arg e "$ext" '.[$e] | to_entries[0].value | has("pgrx") or has("rust")' "$versions_file" >/dev/null && continue

  pname=$(sed -n 's/.*pname = "\(.*\)".*/\1/p' "$nixfile" | head -1)
  owner=$(sed -n 's/.*owner = "\(.*\)".*/\1/p' "$nixfile" | head -1)
  repo=$(sed -n 's/.*repo = "\(.*\)".*/\1/p' "$nixfile" | head -1)
  [ -n "$repo" ] || repo="$pname"
  [ -n "$owner" ] || { echo "skip $ext: no owner"; continue; }

  latest_tag=$(gh api "repos/$owner/$repo/tags" --jq '.[0].name' 2>/dev/null) || { echo "skip $ext: tags lookup failed"; continue; }
  [ -n "$latest_tag" ] || continue

  jq -e --arg e "$ext" --arg t "$latest_tag" \
    '.[$e] | to_entries | any(.value.revision == $t or .value.rev == $t or ("v" + .key) == $t or .key == $t)' \
    "$versions_file" >/dev/null && continue

  candidate="${latest_tag#v}"
  url="https://github.com/$owner/$repo/archive/$latest_tag.tar.gz"
  hash=$(nix-prefetch-url --type sha256 --unpack "$url" 2>/dev/null | tail -1) || { echo "skip $ext: prefetch failed for $latest_tag"; continue; }
  sri_hash=$(nix hash to-sri --type sha256 "$hash")
  postgresql=$(jq -c --arg e "$ext" '.[$e] | to_entries | max_by(.key) | .value.postgresql' "$versions_file")

  jq --arg e "$ext" --arg v "$candidate" --arg rev "$latest_tag" --arg hash "$sri_hash" --argjson pg "$postgresql" \
    '.[$e][$v] = {postgresql: $pg, revision: $rev, rev: $rev, hash: $hash}' \
    "$versions_file" > "$versions_file.tmp" && mv "$versions_file.tmp" "$versions_file"

  echo "updated $ext -> $candidate ($latest_tag)"
  changed=1
done

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "changed=$changed" >> "$GITHUB_OUTPUT"
fi
