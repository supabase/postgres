#!/usr/bin/env python3
"""Check nix/ext/versions.json extensions against upstream GitHub tags."""

import json
import os
import re
import subprocess
import sys

REPO_ROOT = subprocess.run(
    ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True
).stdout.strip()
VERSIONS_FILE = os.path.join(REPO_ROOT, "nix/ext/versions.json")

# `exts` attribute name -> versions.json catalog key, where they differ.
ATTR_TO_CATALOG_KEY = {"plan_filter": "pg_plan_filter"}

# Extensions where we don't attempt a hash bump: fetchurl-based source, or a
# cargoHash/pgrx vendor hash that needs an actual build to compute. Version
# gets bumped anyway with a placeholder hash for a human to fill in.
NO_HASH_EXTS = {"pg_graphql", "wrappers", "postgis", "pgroonga"}

CLEAN_TAG_RE = re.compile(r"^(?:v|ver_)?(\d+(?:\.\d+){0,3})$")
LEADING_VERSION_RE = re.compile(r"^(\d+(?:\.\d+)*)")


def parse_version(s: str) -> tuple[int, ...]:
    m = LEADING_VERSION_RE.match(s)
    if not m:
        return (0,)
    return tuple(int(p) for p in m.group(1).split("."))


def best_candidate(tags: list[str], repo: str) -> tuple[tuple[int, ...], str] | None:
    # repo-prefixed underscore tags (wal2json_2_6) - only trusted when the
    # prefix is the actual repo name, not any legacy tag scheme (REL0_9_1).
    prefixed_re = re.compile(
        rf"^{re.escape(repo)}[-_](\d+(?:[._]\d+){{1,3}})$", re.IGNORECASE
    )
    candidates: list[tuple[tuple[int, ...], str]] = []
    for tag in tags:
        m = CLEAN_TAG_RE.match(tag) or prefixed_re.match(tag)
        if not m:
            continue
        version_str = m.group(1).replace("_", ".")
        candidates.append((parse_version(version_str), tag))
    return max(candidates, default=None)


def github_metadata(system: str) -> dict[str, str]:
    expr = (
        "exts: builtins.listToAttrs (map (n: { name = n; value = exts.${n}.github; })"
        " (builtins.filter (n: exts.${n} ? github) (builtins.attrNames exts)))"
    )
    out = subprocess.run(
        [
            "nix",
            "eval",
            "--json",
            f".#legacyPackages.{system}.psql_15.exts",
            "--apply",
            expr,
        ],
        cwd=REPO_ROOT,
        capture_output=True,
        text=True,
        check=True,
    ).stdout
    return json.loads(out)


def fetch_tags(owner: str, repo: str) -> list[str] | None:
    result = subprocess.run(
        ["gh", "api", f"repos/{owner}/{repo}/tags", "--paginate"],
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return [t["name"] for t in json.loads(result.stdout)]


def prefetch_hash(owner: str, repo: str, tag: str) -> str | None:
    url = f"https://github.com/{owner}/{repo}/archive/{tag}.tar.gz"
    prefetch = subprocess.run(
        ["nix-prefetch-url", "--type", "sha256", "--unpack", url],
        capture_output=True,
        text=True,
    )
    if prefetch.returncode != 0:
        return None
    sha256 = prefetch.stdout.strip().splitlines()[-1]
    sri = subprocess.run(
        ["nix", "hash", "to-sri", "--type", "sha256", sha256],
        capture_output=True,
        text=True,
        check=True,
    )
    return sri.stdout.strip()


def main() -> None:
    system = subprocess.run(
        ["nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem"],
        capture_output=True,
        text=True,
        check=True,
    ).stdout.strip()

    with open(VERSIONS_FILE) as f:
        versions = json.load(f)

    changed = False
    for attr, repo_slug in github_metadata(system).items():
        ext = ATTR_TO_CATALOG_KEY.get(attr, attr)
        if ext not in versions:
            continue
        owner, repo = repo_slug.split("/", 1)

        tags = fetch_tags(owner, repo)
        if tags is None:
            print(f"skip {ext}: tags lookup failed")
            continue

        candidate = best_candidate(tags, repo)
        if candidate is None:
            print(f"skip {ext}: no clean version tags")
            continue
        candidate_version, tag = candidate

        entries = versions[ext]
        current_key = max(entries, key=parse_version)
        if candidate_version <= parse_version(current_key):
            continue

        if ext in NO_HASH_EXTS:
            sri_hash = ""
        else:
            sri_hash = prefetch_hash(owner, repo, tag)
            if sri_hash is None:
                print(f"skip {ext}: prefetch failed for {tag}")
                continue

        version_str = ".".join(str(p) for p in candidate_version)
        entries[version_str] = {
            "postgresql": entries[current_key]["postgresql"],
            "revision": tag,
            "rev": tag,
            "hash": sri_hash,
        }
        changed = True
        suffix = " [no hash, needs manual fill-in]" if not sri_hash else ""
        print(f"updated {ext} -> {version_str} ({tag}){suffix}")

    if changed:
        with open(VERSIONS_FILE, "w") as f:
            json.dump(versions, f, indent=2)
            f.write("\n")

    github_output = os.environ.get("GITHUB_OUTPUT")
    if github_output:
        with open(github_output, "a") as f:
            f.write(f"changed={'true' if changed else 'false'}\n")


if __name__ == "__main__":
    sys.exit(main())
