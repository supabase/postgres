#!/usr/bin/env nu

const ATTR_TO_CATALOG_KEY = {plan_filter: "pg_plan_filter"}

# not a plain GitHub archive (fetchurl, or a cargoHash/pgrx vendor hash)
const NO_HASH_EXTS = ["pg_graphql" "wrappers" "postgis" "pgroonga"]
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

let repo_root = (run ["git" "rev-parse" "--show-toplevel"])
let versions_file = ($repo_root | path join "nix/ext/versions.json")
mut versions = (open $versions_file)
mut changed = false

let exts_expr = "exts: builtins.listToAttrs (map (n: { name = n; value = exts.${n}.github; }) (builtins.filter (n: exts.${n} ? github) (builtins.attrNames exts)))"
let exts_json = (run ["nix" "eval" "--json" $".#legacyPackages.($system).psql_15.exts" "--apply" $exts_expr])
if $exts_json == null { error make {msg: "nix eval of extension metadata failed"} }
let exts = ($exts_json | from json | transpose attr repo_slug)
if ($exts | is-empty) { error make {msg: "no extensions with github metadata found"} }

for it in $exts {
  let ext = ($ATTR_TO_CATALOG_KEY | get -o $it.attr | default $it.attr)
  if not ($ext in ($versions | columns)) { continue }
  let parts = ($it.repo_slug | split row "/")
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

  let sri_hash = if $ext in $NO_HASH_EXTS {
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
