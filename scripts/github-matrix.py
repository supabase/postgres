#!/usr/bin/env python3

import argparse
from collections import defaultdict
import graphlib
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
    drvPath: str
    neededSubstitutes: List[str]
    neededBuilds: List[str]
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


def build_nix_eval_command(max_workers: int, flake_outputs: List[str]) -> List[str]:
    """Build the nix-eval-jobs command with appropriate flags."""
    nix_eval_cmd = [
        "nix-eval-jobs",
        "--flake",
        ".",
        "--check-cache-status",
        "--force-recurse",
        "--quiet",
        "--option",
        "eval-cache",
        "false",
        "--option",
        "accept-flake-config",
        "true",
        "--workers",
        str(max_workers),
        "--select",
        f"outputs: {{ inherit (outputs) {' '.join(flake_outputs)}; }}",
    ]
    return nix_eval_cmd


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

        runs_on_config = BUILD_RUNNER_MAP[data["system"]]

        return {
            "attr": f"{data['attr']}",
            "name": data["name"],
            "system": data["system"],
            "already_cached": data.get("cacheStatus") != "notBuilt",
            "runs_on": runs_on_config,
            "drvPath": data["drvPath"],
            "neededSubstitutes": data.get("neededSubstitutes", []),
            "neededBuilds": data.get("neededBuilds", []),
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
        drv_paths: Set[str] = set()
        assert process.stdout is not None  # for mypy
        assert process.stderr is not None  # for mypy
        for line in process.stdout:
            package = parse_nix_eval_line(line, drv_paths)
            if package:
                yield package

        process.wait()
        if process.returncode != 0:
            print("Error: Evaluation failed", file=sys.stderr)
            sys.stderr.write(process.stderr.read())
            sys.exit(process.returncode)


def is_extension_pkg(pkg: GitHubActionPackage) -> bool:
    """Check if the package is a postgresql extension package."""
    attrs = pkg["attr"].split(".")
    return attrs[-2] == "exts"


# thank you buildbot-nix https://github.com/nix-community/buildbot-nix/blob/985d069a2a45cf4a571a4346107671adc2bd2a16/buildbot_nix/buildbot_nix/build_trigger.py#L297
def sort_pkgs_by_closures(jobs: List[GitHubActionPackage]) -> List[GitHubActionPackage]:
    sorted_jobs = []

    # Prepare job dependencies
    job_set = {job["drvPath"] for job in jobs}
    job_closures = {
        k["drvPath"]: set(k["neededSubstitutes"])
        .union(set(k["neededBuilds"]))
        .intersection(job_set)
        .difference({k["drvPath"]})
        for k in jobs
    }

    sorter = graphlib.TopologicalSorter(job_closures)

    for item in sorter.static_order():
        i = 0
        while i < len(jobs):
            if item == jobs[i]["drvPath"]:
                sorted_jobs.append(jobs[i])
                del jobs[i]
            else:
                i += 1

    return sorted_jobs


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Generate GitHub Actions matrix for Nix builds"
    )
    parser.add_argument(
        "flake_outputs", nargs="+", help="Nix flake outputs to evaluate"
    )

    args = parser.parse_args()

    max_workers: int = os.cpu_count() or 1

    cmd = build_nix_eval_command(max_workers, args.flake_outputs)

    gh_action_packages = sort_pkgs_by_closures(list(run_nix_eval_jobs(cmd)))

    def clean_package_for_output(pkg: GitHubActionPackage) -> dict:
        """Remove debug fields from package for final output"""
        returned_pkg = {
            "attr": pkg["attr"],
            "name": pkg["name"],
            "system": pkg["system"],
            "runs_on": pkg["runs_on"],
        }
        if is_extension_pkg(pkg):
            # Extract PostgreSQL version from attribute path
            attrs = pkg["attr"].split(".")
            returned_pkg["postgresql_version"] = attrs[-3].split("_")[-1]
        return returned_pkg

    # Group packages by system
    grouped_by_system = defaultdict(list)
    for pkg in gh_action_packages:
        if not pkg["already_cached"]:
            grouped_by_system[pkg["system"]].append(clean_package_for_output(pkg))

    # Create output with system-specific matrices
    gh_output = {}
    for system, packages in grouped_by_system.items():
        gh_output[system.replace("-", "_")] = {"include": packages}

    print(
        f"debug: Generated GitHub Actions matrix: {json.dumps(gh_output, indent=2)}",
        file=sys.stderr,
    )
    print(json.dumps(gh_output))


if __name__ == "__main__":
    main()
