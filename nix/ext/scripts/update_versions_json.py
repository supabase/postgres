#!/usr/bin/env nix-shell
#! nix-shell -i python3 -p python3 git nix-prefetch-git python3Packages.packaging

import subprocess
import json
import argparse
from pathlib import Path
from typing import Dict, List, Union
from packaging.version import parse as parse_version, InvalidVersion

Schema = Dict[str, Dict[str, Dict[str, Union[List[str], str, bool]]]]

POSTGRES_VERSIONS: List[str] = ["15", "17"]
VERSIONS_JSON_PATH = "versions.json"


def run(cmd: List[str]) -> str:
    result = subprocess.run(cmd, capture_output=True, text=True, check=True)
    return result.stdout.strip()


def get_tags(url: str) -> Dict[str, str]:
    output = run(["git", "ls-remote", "--tags", url])
    tags: Dict[str, str] = {}
    for line in output.splitlines():
        if "^{}" not in line:
            parts = line.split("\t")
            if len(parts) == 2:
                commit_hash, ref = parts
                if ref.startswith("refs/tags/"):
                    tag = ref.removeprefix("refs/tags/")
                    try:
                        parse_version(tag)
                    except InvalidVersion:
                        continue
                    tags[tag] = commit_hash
    return tags


def get_sri_hash(url: str, commit_hash: str) -> str:
    output = run(["nix-prefetch-git", "--quiet", "--url", url, "--rev", commit_hash])
    nix_hash = json.loads(output)["sha256"]
    return "sha256-" + run(["nix", "hash", "to-base64", "--type", "sha256", nix_hash])


def load() -> Schema:
    if not Path(VERSIONS_JSON_PATH).exists():
        return {}
    with open(VERSIONS_JSON_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def build(name: str, url: str, data: Schema, ignore: bool = False) -> Schema:
    tags = get_tags(url)
    versions = data.get(name, {})
    for tag, commit_hash in tags.items():
        if tag in versions:
            continue
        if ignore:
            versions[tag] = {"ignore": True}
        else:
            sri_hash = get_sri_hash(url, commit_hash)
            versions[tag] = {"postgresql": POSTGRES_VERSIONS, "hash": sri_hash}
    data[name] = versions
    return data


def save(data: Schema) -> None:
    sorted_data = {}
    for name, versions in data.items():
        sorted_data[name] = dict(
            sorted(versions.items(), key=lambda item: parse_version(item[0]))
        )
    with open(VERSIONS_JSON_PATH, "w", encoding="utf-8") as f:
        json.dump(sorted_data, f, indent=2)
        f.write("\n")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("extension_name")
    parser.add_argument("git_repo_url")
    parser.add_argument("--ignore", action="store_true")
    args = parser.parse_args()

    save(build(args.extension_name, args.git_repo_url, load(), ignore=args.ignore))


if __name__ == "__main__":
    main()
