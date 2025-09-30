#!/usr/bin/env python3

import argparse
import json
import os
import subprocess
import sys
from typing import (
    Any,
    Dict,
    Generator,
    List,
    Literal,
    NotRequired,
    Optional,
    Set,
    TypedDict,
)


class NixEvalJobsOutput(TypedDict):
    """Raw output from nix-eval-jobs command."""

    attr: str
    attrPath: List[str]
    cacheStatus: Literal["notBuilt", "cached", "local"]
    drvPath: str
    isCached: bool
    name: str
    system: str
    neededBuilds: NotRequired[List[Any]]
    neededSubstitutes: NotRequired[List[Any]]
    outputs: NotRequired[Dict[str, str]]


class RunsOnConfig(TypedDict):
    """GitHub Actions runs-on configuration."""

    group: NotRequired[str]
    labels: List[str]


class GitHubActionPackage(TypedDict):
    """Processed package for GitHub Actions matrix."""

    attr: str
    name: str
    system: str
    already_cached: bool
    runs_on: RunsOnConfig
    postgresql_version: NotRequired[str]


BUILD_RUNNER_MAP: Dict[str, RunsOnConfig] = {
    "aarch64-linux": {
        "group": "self-hosted-runners-nix",
        "labels": ["aarch64-linux"],
    },
    "aarch64-darwin": {
        "group": "self-hosted-runners-nix",
        "labels": ["aarch64-darwin"],
    },
    "x86_64-linux": {
        "labels": ["blacksmith-32vcpu-ubuntu-2404"],
    },
}


def get_worker_count() -> int:
    """Get optimal worker count based on CPU cores."""
    try:
        return max(1, int(os.cpu_count()))
    except (OSError, AttributeError):
        print(
            "Warning: Unable to get CPU count, using default max_workers=1",
            file=sys.stderr,
        )
        return 1


def build_nix_eval_command(max_workers: int, target: str) -> List[str]:
    """Build the nix-eval-jobs command with appropriate flags."""
    nix_eval_cmd = [
        "nix-eval-jobs",
        "--flake",
        f".#{target}",
        "--check-cache-status",
        "--force-recurse",
        "--quiet",
        "--workers",
        str(max_workers),
    ]
    return nix_eval_cmd


def parse_nix_eval_line(
    line: str, drv_paths: Set[str], target: str
) -> Optional[GitHubActionPackage]:
    """Parse a single line of nix-eval-jobs output"""
    if not line.strip():
        return None

    try:
        data: NixEvalJobsOutput = json.loads(line)
        if data["drvPath"] in drv_paths:
            return None
        drv_paths.add(data["drvPath"])

        runs_on_config = BUILD_RUNNER_MAP[data["system"]]

        return {
            "attr": f"{target}.{data['attr']}",
            "name": data["name"],
            "system": data["system"],
            "already_cached": data.get("cacheStatus") != "notBuilt",
            "runs_on": runs_on_config,
        }
    except json.JSONDecodeError:
        print(f"Skipping invalid JSON line: {line}", file=sys.stderr)
        return None


def run_nix_eval_jobs(
    cmd: List[str], target: str
) -> Generator[GitHubActionPackage, None, None]:
    """Run nix-eval-jobs and yield parsed package data."""
    print(f"Running command: {' '.join(cmd)}", file=sys.stderr)

    with subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    ) as process:
        drv_paths = set()

        for line in process.stdout:
            package = parse_nix_eval_line(line, drv_paths, target)
            if package and not package["already_cached"]:
                print(f"Found package: {package['attr']}", file=sys.stderr)
                yield package

        if process.returncode and process.returncode != 0:
            print("Error: Evaluation failed", file=sys.stderr)
            sys.stderr.write(process.stderr.read())
            sys.exit(process.returncode)


def is_extension_pkg(pkg: GitHubActionPackage) -> bool:
    """Check if the package is a postgresql extension package."""
    attrs = pkg["attr"].split(".")
    return attrs[-2] == "exts"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate GitHub Actions matrix for Nix builds"
    )
    parser.add_argument(
        "target", choices=["checks", "extensions"], help="Type of matrix to generate"
    )

    args = parser.parse_args()

    max_workers = get_worker_count()

    if args.target == "checks":
        flake_output = "checks"
    else:
        flake_output = "legacyPackages"

    cmd = build_nix_eval_command(max_workers, flake_output)

    gh_action_packages = list(run_nix_eval_jobs(cmd, flake_output))

    if args.target == "extensions":
        # filter to only include extension packages and add postgresql_version field
        gh_action_packages = [
            {**pkg, "postgresql_version": pkg["attr"].split(".")[-3]}
            for pkg in gh_action_packages
            if is_extension_pkg(pkg)
        ]

        # Group packages by system
        grouped_by_system = {}
        for pkg in gh_action_packages:
            system = pkg["system"]
            if system not in grouped_by_system:
                grouped_by_system[system] = []
            grouped_by_system[system].append(pkg)

        # Create output with system-specific matrices
        gh_output = {}
        for system, packages in grouped_by_system.items():
            gh_output[system.replace("-", "_")] = {"include": packages}
    else:
        gh_output = {"include": gh_action_packages}

    print(json.dumps(gh_output))


if __name__ == "__main__":
    main()
