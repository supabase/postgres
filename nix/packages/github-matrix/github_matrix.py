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

System = Literal["x86_64-linux", "aarch64-linux", "aarch64-darwin"]
RunnerType = Literal["ephemeral", "self-hosted"]


class NixEvalJobsOutput(TypedDict):
    """Raw output from nix-eval-jobs command."""

    attr: str
    attrPath: List[str]
    cacheStatus: Literal["notBuilt", "cached", "local"]
    drvPath: str
    name: str
    system: System
    neededBuilds: NotRequired[List[Any]]
    neededSubstitutes: NotRequired[List[Any]]
    outputs: NotRequired[Dict[str, str]]
    error: NotRequired[str]
    requiredSystemFeatures: NotRequired[List[str]]


class RunsOnConfig(TypedDict):
    """GitHub Actions runs-on configuration."""

    group: NotRequired[str]
    labels: List[str]


class GitHubActionPackage(TypedDict):
    """Final package output for GitHub Actions matrix."""

    attr: str
    name: str
    system: System
    runs_on: RunsOnConfig
    postgresql_version: NotRequired[str]


BUILD_RUNNER_MAP: Dict[RunnerType, Dict[System, RunsOnConfig]] = {
    "ephemeral": {
        "aarch64-linux": {
            "labels": ["blacksmith-8vcpu-ubuntu-2404-arm"],
        },
        "x86_64-linux": {
            "labels": ["blacksmith-8vcpu-ubuntu-2404"],
        },
    },
    "self-hosted": {
        "aarch64-darwin": {
            "group": "self-hosted-runners-nix",
            "labels": ["aarch64-darwin"],
        },
        "aarch64-linux": {
            "group": "self-hosted-runners-nix",
            "labels": ["aarch64-linux"],
        },
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


def parse_nix_eval_line(line: str, drv_paths: Set[str]) -> Optional[NixEvalJobsOutput]:
    """Parse a single line of nix-eval-jobs output"""
    if not line.strip():
        return None

    try:
        data: NixEvalJobsOutput = json.loads(line)
        if "error" in data:
            raise ValueError(
                f"Error in nix-eval-jobs output for {data['attr']}: {data['error']}"
            )
        if data["drvPath"] in drv_paths:
            return None
        drv_paths.add(data["drvPath"])
        return data
    except json.JSONDecodeError:
        print(f"Skipping invalid JSON line: {line}", file=sys.stderr)
        return None


def run_nix_eval_jobs(cmd: List[str]) -> Generator[NixEvalJobsOutput, None, None]:
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


def is_extension_pkg(pkg: NixEvalJobsOutput) -> bool:
    """Check if the package is a postgresql extension package."""
    attrs = pkg["attr"].split(".")
    return attrs[-2] == "exts"


# thank you buildbot-nix https://github.com/nix-community/buildbot-nix/blob/985d069a2a45cf4a571a4346107671adc2bd2a16/buildbot_nix/buildbot_nix/build_trigger.py#L297
def sort_pkgs_by_closures(jobs: List[NixEvalJobsOutput]) -> List[NixEvalJobsOutput]:
    sorted_jobs = []

    # Prepare job dependencies
    job_set = {job["drvPath"] for job in jobs}
    job_closures = {
        k["drvPath"]: set(k.get("neededSubstitutes", []))
        .union(set(k.get("neededBuilds", [])))
        .intersection(job_set)
        .difference({k["drvPath"]})
        for k in jobs
    }

    sorter = graphlib.TopologicalSorter(job_closures)

    job_by_drv = {job["drvPath"]: job for job in jobs}
    for item in sorter.static_order():
        if item in job_by_drv:
            sorted_jobs.append(job_by_drv[item])

    return sorted_jobs


def is_large_pkg(pkg: NixEvalJobsOutput) -> bool:
    """Determine if a package is considered large based on its attribute path."""
    return "big-parallel" in pkg.get("requiredSystemFeatures", [])


def is_kvm_pkg(pkg: NixEvalJobsOutput) -> bool:
    """Determine if a package requires KVM"""
    return "kvm" in pkg.get("requiredSystemFeatures", [])


def get_runner_for_package(pkg: NixEvalJobsOutput) -> RunsOnConfig | None:
    """Determine the appropriate GitHub Actions runner for a package.

    Priority order:
    1. KVM packages → self-hosted runners
    2. Large packages on Linux → 32vcpu ephemeral runners
    3. Darwin packages → self-hosted runners
    4. Default → ephemeral runners
    """
    system = pkg["system"]

    if is_kvm_pkg(pkg):
        runConfig = BUILD_RUNNER_MAP["self-hosted"].get(system)
        if runConfig is None:
            raise ValueError(
                f"No self-hosted with kvm support available for system: {system}"
            )
        return runConfig

    if is_large_pkg(pkg) and system in ("x86_64-linux", "aarch64-linux"):
        suffix = "-arm" if system == "aarch64-linux" else ""
        return {"labels": [f"blacksmith-32vcpu-ubuntu-2404{suffix}"]}

    if system == "aarch64-darwin":
        return BUILD_RUNNER_MAP["self-hosted"]["aarch64-darwin"]

    return BUILD_RUNNER_MAP["ephemeral"].get(system)


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

    def clean_package_for_output(pkg: NixEvalJobsOutput) -> GitHubActionPackage:
        """Convert nix-eval-jobs output to GitHub Actions matrix package"""
        runner = get_runner_for_package(pkg)
        if runner is None:
            raise ValueError(f"No runner configuration for system: {pkg['system']}")
        returned_pkg: GitHubActionPackage = {
            "attr": pkg["attr"],
            "name": pkg["name"],
            "system": pkg["system"],
            "runs_on": runner,
        }
        if is_extension_pkg(pkg):
            # Extract PostgreSQL version from attribute path
            attrs = pkg["attr"].split(".")
            returned_pkg["postgresql_version"] = attrs[-3].split("_")[-1]
        return returned_pkg

    # Group packages by system
    grouped_by_system = defaultdict(list)
    for pkg in gh_action_packages:
        if pkg.get("cacheStatus") == "notBuilt":
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
