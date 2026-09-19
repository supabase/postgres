#!/usr/bin/env bash
set -euo pipefail

# Prototype: parallel eval -> nix-eval-jobs-shaped JSONL -> github-matrix.
# Native system only (DetNix currently breaks on foreign-system eval).
# Run from the repo root.

PG_VERSION=${1:?usage: $0 <15|17|orioledb-17|common>}
CACHE_URL=https://nix-postgres-artifacts.s3.amazonaws.com
SYSTEM=$(nix eval --raw --no-pure-eval --expr builtins.currentSystem)
workdir=$(mktemp -d)
trap 'rm -rf "$workdir"' EXIT

cat >"$workdir/walk.nix" <<-'EOF'
	{ prefix, pgVersion, v }:
	let
	  # top-level attrs are grouped by the pg major in their name
	  # (psql_15, psql_17_slim, postgresql_orioledb-17_src, site-env-15, ...)
	  pgVersionOf = n:
	    if builtins.match ".*orioledb-17.*" n != null then "orioledb-17"
	    else if builtins.match "(.*[_-])?17([_-].*)?" n != null then "17"
	    else if builtins.match "(.*[_-])?15([_-].*)?" n != null then "15"
	    else "common";
	  names = builtins.filter (n: pgVersionOf n == pgVersion) (builtins.attrNames v);
	  selected = builtins.listToAttrs (map (n: { name = n; value = v.${n}; }) names);
	  isDrv = x: (x.type or null) == "derivation";
	  esc = s: if builtins.match "[a-zA-Z_][a-zA-Z0-9_'-]*" s != null then s else "\"${s}\"";
	  join = p: builtins.concatStringsSep "." (map esc p);
	  # lib.lazyDerivation (NixOS tests) hides requiredSystemFeatures from the
	  # attrset, so read it from the .drv like nix-eval-jobs did
	  words = s: builtins.filter (w: builtins.isString w && w != "") (builtins.split " " s);
	  drvFeatures = x:
	    let found = builtins.filter builtins.isList
	      (builtins.split "\\(\"requiredSystemFeatures\",\"([^\"]*)\"\\)" (builtins.readFile x.drvPath));
	    in if found == [ ] then [ ] else words (builtins.head (builtins.head found));
	  go = p: x:
	    if isDrv x then
	      let
	        val = {
	          attr = join p;
	          attrPath = p;
	          name = x.name;
	          system = x.system;
	          drvPath = x.drvPath;
	          outputs = builtins.listToAttrs
	            (map (o: { name = o; value = x.${o}.outPath; }) (x.outputs or [ "out" ]));
	          requiredSystemFeatures = x.requiredSystemFeatures or (drvFeatures x);
	        };
	        r = builtins.tryEval (builtins.deepSeq val val);
	      in if r.success then [ r.value ] else [ { attr = join p; error = "evaluation failed"; } ]
	    else if builtins.isAttrs x then
	      # each child subtree is deeply forced as one unit; builtins.parallel
	      # evaluates the units concurrently, then we splice the results
	      let
	        branches = map
	          (n: let jobs = go (p ++ [ n ]) x.${n}; in builtins.deepSeq jobs jobs)
	          (builtins.attrNames x);
	        spliced = builtins.concatLists branches;
	      in if builtins ? parallel then builtins.parallel branches spliced else spliced
	    else [ ];
	in go prefix selected
EOF

# builtins.parallel needs an experimental feature that only Determinate Nix has;
# eval-cores defaults to 1, so without it the "parallel" eval is single-threaded
parallel_flags=()
if nix --version 2>/dev/null | grep -qi determinate; then
	parallel_flags=(--extra-experimental-features parallel-eval --option eval-cores 0)
fi

for output in checks legacyPackages; do
	echo "== evaluating $output.$SYSTEM ($PG_VERSION)" >&2
	time nix eval --json --no-pure-eval --option eval-cache false \
		"${parallel_flags[@]}" \
		".#$output.$SYSTEM" \
		--apply "v: import $workdir/walk.nix { prefix = [ \"$output\" \"$SYSTEM\" ]; pgVersion = \"$PG_VERSION\"; inherit v; }" \
		>"$workdir/$output.json"
done

# distinct output-path hashes -> parallel narinfo HEAD sweep
jq -r '.[] | select(.error == null) | .outputs[]' \
	"$workdir"/checks.json "$workdir"/legacyPackages.json |
	sed -E 's|^/nix/store/([a-z0-9]{32})-.*|\1|' | sort -u >"$workdir/hashes.txt"

echo "== checking $(wc -l <"$workdir/hashes.txt") narinfos against $CACHE_URL" >&2
awk -v base="$CACHE_URL" \
	'{ printf "url = \"%s/%s.narinfo\"\noutput = \"/dev/null\"\n", base, $0 }' \
	<"$workdir/hashes.txt" >"$workdir/curl.cfg"
time curl --parallel --parallel-max 100 --head --silent \
	--write-out '%{http_code} %{url}\n' --config "$workdir/curl.cfg" |
	awk '$1 == "200" { sub(/.*\//, "", $2); sub(/\.narinfo$/, "", $2); print $2 }' \
		>"$workdir/cached.txt" || true

# a job is "cached" only if every one of its outputs is in the cache
jq -c --rawfile cached "$workdir/cached.txt" '
  (($cached | split("\n")) | map(select(length > 0)) | map({(.): true}) | add // {}) as $c
  | .[]
  | if .error != null then . else
      . + { cacheStatus:
              (if ([ .outputs[] | capture("^/nix/store/(?<h>[a-z0-9]{32})-").h ]
                   | all($c[.] // false))
               then "cached" else "notBuilt" end) }
    end
' "$workdir"/checks.json "$workdir"/legacyPackages.json | tee "$workdir/jobs.jsonl"

echo "== $(wc -l <"$workdir/jobs.jsonl") jobs, $(jq -sr 'map(select(.cacheStatus == "notBuilt")) | length' "$workdir/jobs.jsonl") notBuilt" >&2
