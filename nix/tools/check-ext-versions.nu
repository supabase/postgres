#!/usr/bin/env nu

const OVERRIDES = {
  pg_graphql: {noHash: true}
  pg_plan_filter: {repo: "pgexperts/pg_plan_filter"}
  pgroonga: {repo: "pgroonga/pgroonga", noHash: true}
  postgis: {repo: "postgis/postgis", noHash: true}
  wrappers: {noHash: true}
}

const FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

def run [command: list<string>] {
  run-external ...$command | complete
  | if $in.exit_code == 0 { $in.stdout | str trim } else { null }
}

def parse-version [text: string] {
  $text
  | parse --regex '^(\d+(?:\.\d+)*)'
  | if ($in | is-empty) {
    [0]
  } else {
    $in.0.capture0 | split row "." | each { into int }
  }
}

def is-newer [current: list<int>, candidate: list<int>] {
  let highest = ([{v: $current}, {v: $candidate}] | sort-by v | last | get v)
  $candidate != $current and $highest == $candidate
}

def best-candidate [tags: list<string>, repo: string] {
  let prefixed = ("^" + $repo + "[-_](\\d+(?:[._]\\d+){1,3})$")
  let candidates = (
    $tags
    | each { |tag|
      let dtag = ($tag | str downcase)
      let match = (
        $dtag
        | parse --regex '^(?:v|ver_)?(\d+(?:\.\d+){0,3})$'
        | if ($in | is-empty) { $dtag | parse --regex $prefixed } else { $in }
      )
      if ($match | is-empty) {
        null
      } else {
        let version = ($match.0.capture0 | str replace --all "_" ".")
        {v: (parse-version $version), tag: $tag}
      }
    }
    | compact
  )
  if ($candidates | is-empty) { null } else { $candidates | sort-by v | last }
}

let system = (run ["nix" "eval" "--impure" "--raw" "--expr" "builtins.currentSystem"])
if $system == null {
  error make {msg: "nix eval of builtins.currentSystem failed"}
}

let derived = (
  run ["nix" "eval" "--json" $".#legacyPackages.($system).extUpdateRepos"]
  | if $in == null {
    error make {msg: "nix eval of derived repos failed"}
  } else {
    $in | from json
  }
)

let repo_root = (run ["git" "rev-parse" "--show-toplevel"])
let versions_file = ($repo_root | path join "nix/ext/versions.json")
mut versions = (open $versions_file)
mut changed = false

for ext in ($versions | columns) {
  let override = ($OVERRIDES | get -o $ext)
  let repo_slug = ($override.repo? | default ($derived | get -o $ext))
  if $repo_slug == null {
    let hint = "add it to OVERRIDES in check-ext-versions.nu"
    error make {msg: $"no update source for ($ext) - ($hint)"}
  }
  let no_hash = ($override.noHash? | default false)

  let parts = ($repo_slug | split row "/")
  let owner = $parts.0
  let repo = $parts.1

  let tags = (
    run ["gh" "api" $"repos/($owner)/($repo)/tags" "--paginate"]
    | if $in == null { null } else { $in | from json | get name }
  )
  if $tags == null {
    print $"skip ($ext): tags lookup failed"
    continue
  }

  let candidate = (best-candidate $tags $repo)
  if $candidate == null {
    print $"skip ($ext): no clean version tags"
    continue
  }

  let entries = ($versions | get $ext)
  let current_key = (
    $entries
    | columns
    | each { |k| {k: $k, v: (parse-version $k)} }
    | sort-by v
    | last
    | get k
  )
  if not (is-newer (parse-version $current_key) $candidate.v) { continue }

  let sri_hash = if $no_hash {
    $FAKE_HASH
  } else {
    let url = $"https://github.com/($owner)/($repo)/archive/($candidate.tag).tar.gz"
    run ["nix-prefetch-url" "--type" "sha256" "--unpack" $url]
    | if $in == null {
      null
    } else {
      run ["nix" "hash" "to-sri" "--type" "sha256" ($in | lines | last)]
    }
  }
  if $sri_hash == null {
    print $"skip ($ext): prefetch failed for ($candidate.tag)"
    continue
  }

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
