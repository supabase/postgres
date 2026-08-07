#!/usr/bin/env python3
"""
Generates pg-extension-explorer.html from:
  - nix/ext/version-history.json  (append-only log of frozen historical periods)
  - the live worktree state of nix/config.nix, nix/ext/versions.json,
    nix/ext/supautils.nix, nix/ext/orioledb.nix

If nix/config.nix's postgres/orioledb version fields have changed since the
comparison base (an uncommitted local edit, or --base relative to HEAD in CI),
a new row is appended to version-history.json freezing the *old* state before
regenerating the page for the *new* state.

Usage:
  generate.py                 # write nix/ext/version-history.json + pg-extension-explorer.html
  generate.py --check         # verify committed output is up to date; exit 1 if stale
  generate.py --base <ref>    # ref to diff nix/config.nix against (default: HEAD^)
"""
import argparse
import json
import os
import re
import subprocess
import sys

SCRIPT_DIR = os.path.dirname(os.path.realpath(__file__))


def _git_root():
    # Resolved via git, not relative to __file__: once packaged by Nix this
    # script lives in the store, not in the repo checkout it operates on.
    return subprocess.run(
        ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True, check=True
    ).stdout.strip()


REPO_ROOT = _git_root()
TEMPLATE_PATH = os.path.join(SCRIPT_DIR, "template.html")
HISTORY_PATH = os.path.join(REPO_ROOT, "nix", "ext", "version-history.json")
OUTPUT_PATH = os.path.join(REPO_ROOT, "pg-extension-explorer.html")

CONFIG_NIX_PATH = "nix/config.nix"
VERSIONS_JSON_PATH = "nix/ext/versions.json"
SUPAUTILS_PATH = "nix/ext/supautils.nix"
ORIOLEDB_PATH = "nix/ext/orioledb.nix"

ALL_MAJORS = ["15", "17", "orioledb-17"]

# Display-name overrides where the nix/ext/versions.json key differs from the
# extension's actual package/CREATE EXTENSION name.
NAME_MAP = {
    "http": "pgsql-http",
    "vector": "pgvector",
    "supabase_vault": "vault",
    "safeupdate": "pg-safeupdate",
    "plpgsql_check": "plpgsql-check",
}
CLI_EXTENSIONS = ["supautils", "pg_graphql", "pgsodium", "supabase_vault", "pg_net", "pg_cron", "safeupdate"]


def sh(args):
    return subprocess.run(args, cwd=REPO_ROOT, capture_output=True, text=True, check=True).stdout


def git_show(ref, path):
    return sh(["git", "show", f"{ref}:{path}"])


def git_short_hash(ref):
    return sh(["git", "rev-parse", "--short", ref]).strip()


def git_date(ref):
    return sh(["git", "log", "-1", "--format=%ad", "--date=short", ref]).strip()


def read_worktree(path):
    with open(os.path.join(REPO_ROOT, path)) as f:
        return f.read()


def extract_braced_block(text, key):
    """Returns the content between the {...} that follows `key = {`, matching
    braces by depth so nested "X" = { ... }; blocks don't confuse the extent."""
    m = re.search(rf"\b{re.escape(key)}\s*=\s*\{{", text)
    if not m:
        return None
    depth = 1
    i = m.end()
    start = i
    while i < len(text) and depth > 0:
        if text[i] == "{":
            depth += 1
        elif text[i] == "}":
            depth -= 1
        i += 1
    return text[start : i - 1]


def parse_config_nix(text):
    """{"15": "15.14", "17": "17.6", "orioledb-17": "17_20"} from nix/config.nix content."""
    result = {}
    block = extract_braced_block(text, "postgres")
    if block:
        for vm in re.finditer(r'"(\d+)"\s*=\s*\{\s*version\s*=\s*"([^"]+)"', block):
            result[vm.group(1)] = vm.group(2)
    block = extract_braced_block(text, "orioledb")
    if block:
        for vm in re.finditer(r'"(\d+)"\s*=\s*\{\s*version\s*=\s*"([^"]+)"', block):
            result[f"orioledb-{vm.group(1)}"] = vm.group(2)
    return result


def extract_hardcoded_version(text):
    m = re.search(r'version\s*=\s*"([^"]+)"', text)
    return m.group(1) if m else None


def load_extensions_snapshot(read_file):
    """read_file(path) -> str. Merges versions.json with the hand-pinned
    supautils/orioledb versions into one {key: {version: {...}}} dict."""
    data = dict(json.loads(read_file(VERSIONS_JSON_PATH)))
    sv = extract_hardcoded_version(read_file(SUPAUTILS_PATH))
    ov = extract_hardcoded_version(read_file(ORIOLEDB_PATH))
    data["supautils"] = {sv: {"postgresql": ["15", "17", "orioledb-17"]}}
    data["orioledb"] = {ov: {"postgresql": ["orioledb-17"]}}
    return data


def detect_bump(base_ref):
    """Returns (old_ref, old_versions) if nix/config.nix's version fields
    changed, else None. Prefers an uncommitted local edit (compares against
    HEAD) over --base, so a developer can bump config.nix, run this script,
    and get the freeze before ever committing."""
    dirty = sh(["git", "diff", "--name-only", "--", CONFIG_NIX_PATH]).strip()
    if dirty:
        old_ref = "HEAD"
        old_config = git_show("HEAD", CONFIG_NIX_PATH)
        new_config = read_worktree(CONFIG_NIX_PATH)
    else:
        old_ref = base_ref
        old_config = git_show(base_ref, CONFIG_NIX_PATH)
        new_config = read_worktree(CONFIG_NIX_PATH)

    old_versions = parse_config_nix(old_config)
    new_versions = parse_config_nix(new_config)
    if old_versions == new_versions:
        return None
    return old_ref, old_versions


def maybe_freeze_new_row(history, base_ref):
    bump = detect_bump(base_ref)
    if bump is None:
        return history
    old_ref, old_versions = bump

    row = {
        "commit": git_short_hash(old_ref),
        "date": git_date(old_ref),
        "postgres": old_versions,
        "extensions": load_extensions_snapshot(lambda p: git_show(old_ref, p)),
    }
    print(
        f"Freezing history row from {old_ref} ({row['commit']}, {row['date']}): {old_versions}",
        file=sys.stderr,
    )
    history = dict(history)
    history["periods"] = history["periods"] + [row]
    return history


def get_current_point():
    # Deliberately not tied to HEAD's commit hash: the open/current period has
    # no fixed identity yet, and every commit changes HEAD regardless of
    # whether the tracked extension-defining files changed. Using a real hash
    # here would make the checked-in output go stale on every commit, even
    # unrelated ones.
    return {
        "commit": "current",
        "date": "current",
        "postgres": parse_config_nix(read_worktree(CONFIG_NIX_PATH)),
        "extensions": load_extensions_snapshot(read_worktree),
    }


def build_majors_and_snapshots(history, current):
    points = history["periods"] + [current]
    inception_date = history.get("inception", {}).get("date", points[0]["date"])
    majors = {}
    snapshots = {}

    for major in ALL_MAJORS:
        groups = []
        prev_value = None
        for point in points:
            value = point["postgres"].get(major)
            if value is None:
                continue
            if value != prev_value:
                groups.append({"minor": value, "first": point, "last": point})
                prev_value = value
            else:
                groups[-1]["last"] = point

        entries = []
        for i, g in enumerate(groups):
            start = inception_date if i == 0 else g["first"]["date"]
            end = "current" if i == len(groups) - 1 else groups[i + 1]["first"]["date"]
            rep = g["last"]
            snapshots[rep["commit"]] = rep["extensions"]
            entries.append(
                {
                    "minor": g["minor"],
                    "active": f"{start} → {end}",
                    "snapshot": rep["commit"],
                    "commit": rep["commit"],
                    "date": rep["date"],
                }
            )
        majors[major] = entries

    return majors, snapshots


def render_html(majors, snapshots):
    with open(TEMPLATE_PATH) as f:
        html = f.read()
    html = html.replace("__MAJORS_JSON__", json.dumps(majors))
    html = html.replace("__SNAPSHOTS_JSON__", json.dumps(snapshots))
    html = html.replace("__NAME_MAP_JSON__", json.dumps(NAME_MAP))
    html = html.replace("__CLI_JSON__", json.dumps(CLI_EXTENSIONS))
    return html


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--check", action="store_true", help="verify committed output is up to date; do not write")
    parser.add_argument("--base", default="HEAD^", help="ref to diff nix/config.nix against (default: HEAD^)")
    args = parser.parse_args()

    with open(HISTORY_PATH) as f:
        history = json.load(f)

    history = maybe_freeze_new_row(history, args.base)
    current = get_current_point()
    majors, snapshots = build_majors_and_snapshots(history, current)
    html = render_html(majors, snapshots)
    history_out = json.dumps(history, indent=2) + "\n"

    if args.check:
        with open(HISTORY_PATH) as f:
            committed_history = f.read()
        ok = committed_history == history_out
        if os.path.exists(OUTPUT_PATH):
            with open(OUTPUT_PATH) as f:
                committed_html = f.read()
        else:
            committed_html = None
        ok = ok and committed_html == html

        if not ok:
            if committed_history != history_out:
                print(f"STALE: {HISTORY_PATH} does not match freshly generated output.", file=sys.stderr)
            if committed_html != html:
                print(f"STALE: {OUTPUT_PATH} does not match freshly generated output.", file=sys.stderr)
            print("Run `nix run .#ext-explorer` locally and commit the result.", file=sys.stderr)
            sys.exit(1)
        print("ext-explorer output is up to date.")
        return

    with open(HISTORY_PATH, "w") as f:
        f.write(history_out)
    with open(OUTPUT_PATH, "w") as f:
        f.write(html)
    print(f"Wrote {HISTORY_PATH}")
    print(f"Wrote {OUTPUT_PATH}")


if __name__ == "__main__":
    main()
