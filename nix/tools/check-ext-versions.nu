#!/usr/bin/env nu
# Check nix/ext/versions.json extensions against upstream GitHub tags.

# `exts` attribute name -> versions.json catalog key, where they differ.
const ATTR_TO_CATALOG_KEY = {plan_filter: "pg_plan_filter"}

# fetchurl-based source, or a cargoHash/pgrx vendor hash - not a plain GitHub
# archive, so bump the version with Nix's standard placeholder hash instead.
const NO_HASH_EXTS = ["pg_graphql" "wrappers" "postgis" "pgroonga"]
const FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

def run [command: list<string>] {
  let r = (run-external ...$command | complete)
  if $r.exit_code == 0 { $r.stdout | str trim } else { null }
}

def parse-version [s: string] {
  let m = ($s | parse --regex '^(\d+(?:\.\d+)*)')
  if ($m | is-empty) { [0] } else { $m.0.capture0 | split row "." | each { into int } }
}

def is-newer [current: list<int>, candidate: list<int>] {
  $candidate != $current and ([{v: $current}, {v: $candidate}] | sort-by v | last | get v) == $candidate
}

# repo-prefixed underscore tags (wal2json_2_6) are only trusted when the
# prefix is the actual repo name, not any legacy tag scheme (REL0_9_1).
def best-candidate [tags: list<string>, repo: string] {
  let prefixed = ("^" + $repo + "[-_](\\d+(?:[._]\\d+){1,3})$")
  let candidates = (
    $tags | each { |tag|
      let dtag = ($tag | str downcase)
      let m = ($dtag | parse --regex '^(?:v|ver_)?(\d+(?:\.\d+){0,3})$')
      let m = if ($m | is-empty) { $dtag | parse --regex $prefixed } else { $m }
      if ($m | is-empty) { null } else {
        {v: (parse-version ($m.0.capture0 | str replace --all "_" ".")), tag: $tag}
      }
    } | compact
  )
  if ($candidates | is-empty) { null } else { $candidates | sort-by v | last }
}

def github-metadata [system: string] {
  let expr = "exts: builtins.listToAttrs (map (n: { name = n; value = exts.${n}.github; }) (builtins.filter (n: exts.${n} ? github) (builtins.attrNames exts)))"
  let out = (run ["nix" "eval" "--json" $".#legacyPackages.($system).psql_15.exts" "--apply" $expr])
  if $out == null { error make {msg: "nix eval of extension metadata failed"} }
  $out | from json
}

def fetch-tags [owner: string, repo: string] {
  let out = (run ["gh" "api" $"repos/($owner)/($repo)/tags" "--paginate"])
  if $out == null { null } else { $out | from json | get name }
}

def prefetch-hash [owner: string, repo: string, tag: string] {
  let url = $"https://github.com/($owner)/($repo)/archive/($tag).tar.gz"
  let sha256 = (run ["nix-prefetch-url" "--type" "sha256" "--unpack" $url])
  if $sha256 == null { null } else {
    run ["nix" "hash" "to-sri" "--type" "sha256" ($sha256 | lines | last)]
  }
}

def main [] {
  let system = (run ["nix" "eval" "--impure" "--raw" "--expr" "builtins.currentSystem"])
  if $system == null { error make {msg: "nix eval of builtins.currentSystem failed"} }

  let repo_root = (run ["git" "rev-parse" "--show-toplevel"])
  let versions_file = ($repo_root | path join "nix/ext/versions.json")
  mut versions = (open $versions_file)
  mut changed = false

  for it in (github-metadata $system | transpose attr repo_slug) {
    let ext = ($ATTR_TO_CATALOG_KEY | get -o $it.attr | default $it.attr)
    if not ($ext in ($versions | columns)) { continue }
    let parts = ($it.repo_slug | split row "/")
    let owner = $parts.0
    let repo = $parts.1

    let tags = (fetch-tags $owner $repo)
    if $tags == null { print $"skip ($ext): tags lookup failed"; continue }

    let candidate = (best-candidate $tags $repo)
    if $candidate == null { print $"skip ($ext): no clean version tags"; continue }

    let entries = ($versions | get $ext)
    let current_key = ($entries | columns | each { |k| {k: $k, v: (parse-version $k)} } | sort-by v | last | get k)
    if not (is-newer (parse-version $current_key) $candidate.v) { continue }

    let sri_hash = if $ext in $NO_HASH_EXTS { $FAKE_HASH } else { prefetch-hash $owner $repo $candidate.tag }
    if $sri_hash == null { print $"skip ($ext): prefetch failed for ($candidate.tag)"; continue }

    let version_str = ($candidate.v | each { into string } | str join ".")
    let entry = {
      postgresql: ($entries | get $current_key | get postgresql)
      revision: $candidate.tag
      rev: $candidate.tag
      hash: $sri_hash
    }
    $versions = ($versions | upsert $ext ($entries | upsert $version_str $entry))
    $changed = true
    print $"updated ($ext) -> ($version_str) \(($candidate.tag)\)"
  }

  if $changed {
    $versions | to json --indent 2 | $"($in)\n" | save -f $versions_file
  }
}
