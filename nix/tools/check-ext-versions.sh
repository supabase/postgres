#!/usr/bin/env bash
set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

versions_file="nix/ext/versions.json"
changed=0

# Catalog key -> nix file basename, where they differ.
declare -A file_alias=(
  [http]=pgsql-http
  [plpgsql_check]=plpgsql-check
  [safeupdate]=pg-safeupdate
  [supabase_vault]=vault
  [vector]=pgvector
)

# Catalog key -> "owner/repo", where the nix file's own repo variable/fetcher
# doesn't resolve to the real GitHub repo (fetchurl-based, or repo != pname).
declare -A repo_override=(
  [pg_plan_filter]=pgexperts/pg_plan_filter
  [postgis]=postgis/postgis
  [pgroonga]=pgroonga/pgroonga
)

# Extensions where we don't attempt a hash bump (fetchurl-based source, or a
# cargoHash/pgrx vendor hash that needs an actual build to compute). Version
# gets bumped anyway with a placeholder hash for a human to fill in.
no_hash_exts="pg_graphql wrappers postgis pgroonga"

for ext in $(jq -r 'keys[]' "$versions_file"); do
  base="${file_alias[$ext]:-$ext}"
  nixfile="nix/ext/$base.nix"
  [ -f "$nixfile" ] || nixfile="nix/ext/$base/default.nix"
  [ -f "$nixfile" ] || {
    echo "skip $ext: no nix file found"
    continue
  }

  if [ -n "${repo_override[$ext]:-}" ]; then
    owner="${repo_override[$ext]%%/*}"
    repo="${repo_override[$ext]#*/}"
  else
    pname=$(sed -n 's/.*pname = "\(.*\)".*/\1/p' "$nixfile" | head -1)
    owner=$(sed -n 's/.*owner = "\(.*\)".*/\1/p' "$nixfile" | head -1)
    repo=$(sed -n 's/.*repo = "\(.*\)".*/\1/p' "$nixfile" | head -1)
    if [ -z "$owner" ]; then
      # e.g. `owner = repoOwner;` with `repoOwner = "theory";` defined separately.
      ownervar=$(sed -n 's/.*owner = \([A-Za-z_][A-Za-z0-9_]*\);.*/\1/p' "$nixfile" | head -1)
      [ -n "$ownervar" ] && owner=$(sed -n "s/.*$ownervar = \"\\(.*\\)\".*/\\1/p" "$nixfile" | head -1)
    fi
    [ -n "$repo" ] || repo="$pname"
    [ -n "$owner" ] || {
      echo "skip $ext: no owner"
      continue
    }
  fi

  tags_raw=$(gh api "repos/$owner/$repo/tags" --paginate --jq '.[].name' 2>/dev/null) ||
    {
      echo "skip $ext: tags lookup failed"
      continue
    }

  # Only trust clean vX.Y[.Z...] / ver_X.Y[.Z...] tags, or repo-prefixed
  # underscore tags (wal2json_2_6) - repos also carry packaging/branch tags
  # (debian/1.4.0-2, loader-2.11.0p1, ...) that aren't real releases.
  best=$({
    printf '%s\n' "$tags_raw" |
      grep -E '^(v|ver_)?[0-9]+(\.[0-9]+){1,3}$' |
      while read -r t; do
        v="${t#ver_}"
        v="${v#v}"
        printf '%s\t%s\n' "$v" "$t"
      done
    printf '%s\n' "$tags_raw" |
      grep -E '^[A-Za-z][A-Za-z0-9]*[-_][0-9]+([._][0-9]+){1,3}$' |
      while read -r t; do
        v=$(printf '%s' "$t" | grep -oE '[0-9]+([._][0-9]+){1,3}$' | tr '_' '.')
        printf '%s\t%s\n' "$v" "$t"
      done
  } | sort -t "$(printf '\t')" -k1,1 -V | tail -1) || true
  [ -n "$best" ] || {
    echo "skip $ext: no clean version tags"
    continue
  }
  candidate=$(printf '%s' "$best" | cut -f1)
  tag=$(printf '%s' "$best" | cut -f2)

  current=$(jq -r --arg e "$ext" '.[$e] | keys | max_by(split(".") | map(tonumber? // 0))' "$versions_file")
  highest=$(printf '%s\n%s\n' "$current" "$candidate" | sort -V | tail -1)
  [ "$highest" = "$candidate" ] && [ "$candidate" != "$current" ] || continue

  postgresql=$(jq -c --arg e "$ext" '.[$e] | to_entries | max_by(.key) | .value.postgresql' "$versions_file")

  case " $no_hash_exts " in
    *" $ext "*)
      sri_hash=""
      ;;
    *)
      url="https://github.com/$owner/$repo/archive/$tag.tar.gz"
      hash=$(nix-prefetch-url --type sha256 --unpack "$url" 2>/dev/null | tail -1) || {
        echo "skip $ext: prefetch failed for $tag"
        continue
      }
      sri_hash=$(nix hash to-sri --type sha256 "$hash")
      ;;
  esac

  jq --arg e "$ext" --arg v "$candidate" --arg rev "$tag" --arg hash "$sri_hash" --argjson pg "$postgresql" \
    '.[$e][$v] = {postgresql: $pg, revision: $rev, rev: $rev, hash: $hash}' \
    "$versions_file" >"$versions_file.tmp" && mv "$versions_file.tmp" "$versions_file"

  if [ -z "$sri_hash" ]; then
    echo "updated $ext -> $candidate ($tag) [no hash, needs manual fill-in]"
  else
    echo "updated $ext -> $candidate ($tag)"
  fi
  changed=1
done

if [ -n "${GITHUB_OUTPUT:-}" ]; then
  echo "changed=$changed" >>"$GITHUB_OUTPUT"
fi
