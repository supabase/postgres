#!/usr/bin/env nu

# Extensions whose repo can't be read off the derivation's own src (fetchurl
# instead of fetchFromGitHub, or the package doesn't expose a per-version
# derivation at all). noHash means the real fetcher isn't a plain GitHub
# archive, so skip the hash prefetch and use a placeholder instead.
const OVERRIDES = {
  pg_graphql: {repo: "supabase/pg_graphql", noHash: true}
  pg_hashids: {repo: "iCyberon/pg_hashids"}
  pg_jsonschema: {repo: "supabase/pg_jsonschema"}
  pg_plan_filter: {repo: "pgexperts/pg_plan_filter"}
  pg_stat_monitor: {repo: "percona/pg_stat_monitor"}
  pgjwt: {repo: "michelp/pgjwt"}
  pgroonga: {repo: "pgroonga/pgroonga", noHash: true}
  pgtap: {repo: "theory/pgtap"}
  plpgsql_check: {repo: "okbob/plpgsql_check"}
  postgis: {repo: "postgis/postgis", noHash: true}
  rum: {repo: "postgrespro/rum"}
  timescaledb: {repo: "timescale/timescaledb"}
  wal2json: {repo: "eulerto/wal2json"}
  wrappers: {repo: "supabase/wrappers", noHash: true}
}

const FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

def run [command: list<string>] {
  let result = (run-external ...$command | complete)
  if $result.exit_code == 0 { $result.stdout | str trim } else { null }
}

def parse-version [text: string] {
  let match = ($text | parse --regex '^(\d+(?:\.\d+)*)')
  if ($match | is-empty) { [0] } else { $match.0.capture0 | split row "." | each { into int } }
}

def is-newer [current: list<int>, candidate: list<int>] {
  $candidate != $current and ([{v: $current}, {v: $candidate}] | sort-by v | last | get v) == $candidate
}

def best-candidate [tags: list<string>, repo: string] {
  let prefixed = ("^" + $repo + "[-_](\\d+(?:[._]\\d+){1,3})$")
  let candidates = (
    $tags | each { |tag|
      let dtag = ($tag | str downcase)
      let match = ($dtag | parse --regex '^(?:v|ver_)?(\d+(?:\.\d+){0,3})$')
      let match = if ($match | is-empty) { $dtag | parse --regex $prefixed } else { $match }
      if ($match | is-empty) { null } else {
        {v: (parse-version ($match.0.capture0 | str replace --all "_" ".")), tag: $tag}
      }
    } | compact
  )
  if ($candidates | is-empty) { null } else { $candidates | sort-by v | last }
}

let system = (run ["nix" "eval" "--impure" "--raw" "--expr" "builtins.currentSystem"])
if $system == null { error make {msg: "nix eval of builtins.currentSystem failed"} }

# reads owner/repo straight off each package's own fetchFromGitHub src, where
# it's exposed as a per-version derivation - null where it isn't (see OVERRIDES)
let derive_expr = "exts: builtins.listToAttrs (map (n: let pkg = exts.${n}; pv = if pkg ? perVersion then pkg.perVersion else { }; keys = builtins.attrNames pv; entry = if keys != [ ] then pv.${builtins.head keys} else { }; src = if entry ? src then entry.src else { }; in { name = n; value = if (src ? owner) && (src ? repo) then src.owner + \"/\" + src.repo else null; }) (builtins.attrNames exts))"
let derived_json = (run ["nix" "eval" "--json" $".#legacyPackages.($system).psql_15.exts" "--apply" $derive_expr])
if $derived_json == null { error make {msg: "nix eval of derived repos failed"} }
let derived = ($derived_json | from json)

let repo_root = (run ["git" "rev-parse" "--show-toplevel"])
let versions_file = ($repo_root | path join "nix/ext/versions.json")
mut versions = (open $versions_file)
mut changed = false

for ext in ($versions | columns) {
  let override = ($OVERRIDES | get -o $ext)
  let repo_slug = if $override != null { $override.repo } else { ($derived | get -o $ext) }
  if $repo_slug == null { error make {msg: $"no update source for ($ext) - add it to OVERRIDES in check-ext-versions.nu"} }
  let no_hash = ($override | get -o noHash | default false)

  let parts = ($repo_slug | split row "/")
  let owner = $parts.0
  let repo = $parts.1

  let tags_json = (run ["gh" "api" $"repos/($owner)/($repo)/tags" "--paginate"])
  if $tags_json == null { print $"skip ($ext): tags lookup failed"; continue }
  let tags = ($tags_json | from json | get name)

  let candidate = (best-candidate $tags $repo)
  if $candidate == null { print $"skip ($ext): no clean version tags"; continue }

  let entries = ($versions | get $ext)
  let current_key = ($entries | columns | each { |k| {k: $k, v: (parse-version $k)} } | sort-by v | last | get k)
  if not (is-newer (parse-version $current_key) $candidate.v) { continue }

  let sri_hash = if $no_hash {
    $FAKE_HASH
  } else {
    let url = $"https://github.com/($owner)/($repo)/archive/($candidate.tag).tar.gz"
    let sha256 = (run ["nix-prefetch-url" "--type" "sha256" "--unpack" $url])
    if $sha256 == null { null } else { run ["nix" "hash" "to-sri" "--type" "sha256" ($sha256 | lines | last)] }
  }
  if $sri_hash == null { print $"skip ($ext): prefetch failed for ($candidate.tag)"; continue }

  let version_str = ($candidate.v | each { into string } | str join ".")
  let entry = {postgresql: ($entries | get $current_key | get postgresql), revision: $candidate.tag, rev: $candidate.tag, hash: $sri_hash}
  $versions = ($versions | upsert $ext ($entries | upsert $version_str $entry))
  $changed = true
  print $"updated ($ext) -> ($version_str) \(($candidate.tag)\)"
}

if $changed {
  $versions | to json --indent 2 | $"($in)\n" | save -f $versions_file
}
