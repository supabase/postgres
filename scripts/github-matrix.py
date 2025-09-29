#!/usr/bin/env python3

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


def build_nix_eval_command(max_workers: int) -> List[str]:
    """Build the nix-eval-jobs command with appropriate flags."""
    return [
        "nix-eval-jobs",
        "--flake",
        ".#checks",
        "--check-cache-status",
        "--force-recurse",
        "--quiet",
        "--workers",
        str(max_workers),
    ]


def parse_nix_eval_line(
    line: str, drv_paths: Set[str]
) -> Optional[GitHubActionPackage]:
    """Parse a single line of nix-eval-jobs output"""
    if not line.strip():
        return None

    try:
        data: NixEvalJobsOutput = json.loads(line)
        if data["drvPath"] in drv_paths:
            return None
        drv_paths.add(data["drvPath"])
        print(f"Processing package: {data}", file=sys.stderr)

        runs_on_config = BUILD_RUNNER_MAP[data["system"]]

        return {
            "attr": "checks." + data["attr"],
            "name": data["name"],
            "system": data["system"],
            "already_cached": data.get("cacheStatus") != "notBuilt",
            "runs_on": runs_on_config,
        }
    except json.JSONDecodeError:
        print(f"Skipping invalid JSON line: {line}", file=sys.stderr)
        return None


def run_nix_eval_jobs(cmd: List[str]) -> Generator[GitHubActionPackage, None, None]:
    """Run nix-eval-jobs and yield parsed package data."""
    print(f"Running command: {' '.join(cmd)}", file=sys.stderr)

    with subprocess.Popen(
        cmd, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    ) as process:
        drv_paths = set()

        for line in process.stdout:
            package = parse_nix_eval_line(line, drv_paths)
            if package:
                yield package

        if process.returncode and process.returncode != 0:
            print("Error: Evaluation failed", file=sys.stderr)
            sys.stderr.write(process.stderr.read())
            sys.exit(process.returncode)


def main() -> None:
    max_workers = get_worker_count()
    cmd = build_nix_eval_command(max_workers)

    gh_action_packages = list(run_nix_eval_jobs(cmd))
    gh_output = {"include": gh_action_packages}
    print(json.dumps(gh_output))


if __name__ == "__main__":
    main()
