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

# fetchurl-based source, or a cargoHash/pgrx vendor hash - not a plain GitHub
# archive, so bump the version with Nix's standard placeholder hash instead.
NO_HASH_EXTS = {"pg_graphql", "wrappers", "postgis", "pgroonga"}
FAKE_HASH = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="

CLEAN_TAG_RE = re.compile(r"^(?:v|ver_)?(\d+(?:\.\d+){0,3})$")
LEADING_VERSION_RE = re.compile(r"^(\d+(?:\.\d+)*)")


def run(*args: str) -> str | None:
    result = subprocess.run(args, capture_output=True, text=True, cwd=REPO_ROOT)
    return result.stdout.strip() if result.returncode == 0 else None


def parse_version(s: str) -> tuple[int, ...]:
    m = LEADING_VERSION_RE.match(s)
    return tuple(int(p) for p in m.group(1).split(".")) if m else (0,)


def best_candidate(tags: list[str], repo: str) -> tuple[tuple[int, ...], str] | None:
    # repo-prefixed underscore tags (wal2json_2_6) - only trusted when the
    # prefix is the actual repo name, not any legacy tag scheme (REL0_9_1).
    prefixed_re = re.compile(
        rf"^{re.escape(repo)}[-_](\d+(?:[._]\d+){{1,3}})$", re.IGNORECASE
    )
    versions = []
    for tag in tags:
        m = CLEAN_TAG_RE.match(tag) or prefixed_re.match(tag)
        if m:
            versions.append((parse_version(m.group(1).replace("_", ".")), tag))
    return max(versions, default=None)


def github_metadata(system: str) -> dict[str, str]:
    expr = (
        "exts: builtins.listToAttrs (map (n: { name = n; value = exts.${n}.github; })"
        " (builtins.filter (n: exts.${n} ? github) (builtins.attrNames exts)))"
    )
    out = run(
        "nix",
        "eval",
        "--json",
        f".#legacyPackages.{system}.psql_15.exts",
        "--apply",
        expr,
    )
    assert out, "nix eval of extension metadata failed"
    return json.loads(out)


def fetch_tags(owner: str, repo: str) -> list[str] | None:
    out = run("gh", "api", f"repos/{owner}/{repo}/tags", "--paginate")
    return [t["name"] for t in json.loads(out)] if out is not None else None


def prefetch_hash(owner: str, repo: str, tag: str) -> str | None:
    url = f"https://github.com/{owner}/{repo}/archive/{tag}.tar.gz"
    sha256 = run("nix-prefetch-url", "--type", "sha256", "--unpack", url)
    if sha256 is None:
        return None
    return run("nix", "hash", "to-sri", "--type", "sha256", sha256.splitlines()[-1])


def main() -> None:
    system = run("nix", "eval", "--impure", "--raw", "--expr", "builtins.currentSystem")
    assert system, "nix eval of builtins.currentSystem failed"

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
            sri_hash = FAKE_HASH
        else:
            sri_hash = prefetch_hash(owner, repo, tag)
            if sri_hash is None:
                print(f"skip {ext}: prefetch failed for {tag}")
                continue

        version_str = ".".join(map(str, candidate_version))
        entries[version_str] = {
            "postgresql": entries[current_key]["postgresql"],
            "revision": tag,
            "rev": tag,
            "hash": sri_hash,
        }
        changed = True
        print(f"updated {ext} -> {version_str} ({tag})")

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
