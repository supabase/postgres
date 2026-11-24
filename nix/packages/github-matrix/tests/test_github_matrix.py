#!/usr/bin/env python3

import json

import pytest

from github_matrix import (
    NixEvalJobsOutput,
    build_select_expr,
    get_runner_for_package,
    is_extension_pkg,
    is_virt_pkg,
    is_large_pkg,
    select_system_matrices,
    sort_pkgs_by_closures,
    waits_for_other_jobs,
)


class TestIsExtensionPkg:
    def test_extension_package(self):
        pkg: NixEvalJobsOutput = {
            "attr": "legacyPackages.x86_64-linux.psql_15.exts.pg_cron",
            "attrPath": [
                "legacyPackages",
                "x86_64-linux",
                "psql_15",
                "exts",
                "pg_cron",
            ],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/test.drv",
            "name": "pg_cron",
            "system": "x86_64-linux",
        }
        assert is_extension_pkg(pkg) is True

    def test_non_extension_package(self):
        pkg: NixEvalJobsOutput = {
            "attr": "legacyPackages.x86_64-linux.psql_15",
            "attrPath": ["legacyPackages", "x86_64-linux", "psql_15"],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/test.drv",
            "name": "postgresql-16.0",
            "system": "x86_64-linux",
        }
        assert is_extension_pkg(pkg) is False


class TestIsLargePkg:
    @pytest.mark.parametrize(
        "attr,expected",
        [
            ("legacyPackages.x86_64-linux.psql_15.exts.wrappers", True),
            ("legacyPackages.x86_64-linux.psql_15.exts.pg_jsonschema", True),
            ("legacyPackages.x86_64-linux.psql_15.exts.pg_graphql", True),
            ("legacyPackages.x86_64-linux.psql_15.exts.postgis", True),
            ("legacyPackages.x86_64-linux.psql_15.exts.pg_cron", False),
            ("legacyPackages.x86_64-linux.psql_15", False),
        ],
    )
    def test_large_package_detection(self, attr: str, expected: bool):
        pkg: NixEvalJobsOutput = {
            "attr": attr,
            "attrPath": attr.split("."),
            "cacheStatus": "notBuilt",
            "drvPath": f"/nix/store/{attr}.drv",
            "name": attr.split(".")[-1],
            "system": "x86_64-linux",
            "requiredSystemFeatures": ["big-parallel"] if expected else [],
        }
        assert is_large_pkg(pkg) is expected


class TestIsVirtPkg:
    @pytest.mark.parametrize(
        "feat,expected",
        [
            ("", False),
            ("apple-virt", True),
            ("big-parallel", False),
            ("kvm", True),
        ],
    )
    def test_is_virt_pkg(self, feat, expected):
        pkg: NixEvalJobsOutput = {
            "requiredSystemFeatures": [feat],
        }
        assert is_virt_pkg(pkg) is expected


class TestGetRunnerForPackage:
    @pytest.mark.parametrize(
        "system,feature,expected",
        [
            (
                "aarch64-darwin",
                "apple-virt",
                {"labels": ["blacksmith-6vcpu-macos-26"]},
            ),
            (
                "aarch64-darwin",
                "big-parallel",
                {"labels": ["blacksmith-12vcpu-macos-26"]},
            ),
            (
                "aarch64-darwin",
                None,
                {"labels": ["blacksmith-6vcpu-macos-26"]},
            ),
            (
                "aarch64-linux",
                "kvm",
                {"labels": ["blacksmith-8vcpu-ubuntu-2404-arm"]},
            ),
            (
                "aarch64-linux",
                "big-parallel",
                {"labels": ["blacksmith-32vcpu-ubuntu-2404-arm"]},
            ),
            (
                "aarch64-linux",
                None,
                {"labels": ["blacksmith-8vcpu-ubuntu-2404-arm"]},
            ),
            (
                "x86_64-linux",
                "kvm",
                {"labels": ["blacksmith-8vcpu-ubuntu-2404"]},
            ),
            (
                "x86_64-linux",
                "big-parallel",
                {"labels": ["blacksmith-32vcpu-ubuntu-2404"]},
            ),
            (
                "x86_64-linux",
                None,
                {"labels": ["blacksmith-8vcpu-ubuntu-2404"]},
            ),
        ],
    )
    def test_get_runner_for_package(self, system, feature, expected):
        pkg: NixEvalJobsOutput = {
            "system": system,
        }
        if feature:
            pkg["requiredSystemFeatures"] = [feature]

        result = get_runner_for_package(pkg)
        assert result == expected


class TestSortPkgsByClosures:
    def test_empty_list(self):
        result = sort_pkgs_by_closures([])
        assert result == []

    def test_single_package(self):
        pkg: NixEvalJobsOutput = {
            "attr": "packages.x86_64-linux.psql_15",
            "attrPath": ["packages", "x86_64-linux", "psql_15"],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/test.drv",
            "name": "postgresql-16.0",
            "system": "x86_64-linux",
        }
        result = sort_pkgs_by_closures([pkg])
        assert result == [pkg]

    def test_dependency_order(self):
        pkg1: NixEvalJobsOutput = {
            "attr": "packages.x86_64-linux.lib",
            "attrPath": ["packages", "x86_64-linux", "lib"],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/lib.drv",
            "name": "lib",
            "system": "x86_64-linux",
            "neededBuilds": [],
            "neededSubstitutes": [],
        }
        pkg2: NixEvalJobsOutput = {
            "attr": "packages.x86_64-linux.app",
            "attrPath": ["packages", "x86_64-linux", "app"],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/app.drv",
            "name": "app",
            "system": "x86_64-linux",
            "neededBuilds": ["/nix/store/lib.drv"],
            "neededSubstitutes": [],
        }

        # Regardless of input order, lib should come before app
        result = sort_pkgs_by_closures([pkg2, pkg1])
        assert result == [pkg1, pkg2]

        result = sort_pkgs_by_closures([pkg1, pkg2])
        assert result == [pkg1, pkg2]


class TestBuildSelectExpr:
    def test_all_systems(self):
        assert (
            build_select_expr(["checks", "legacyPackages"], None)
            == "outputs: { inherit (outputs) checks legacyPackages; }"
        )

    def test_one_system(self):
        assert build_select_expr(["checks", "legacyPackages"], "aarch64-darwin") == (
            "outputs: { checks.aarch64-darwin = outputs.checks.aarch64-darwin; "
            "legacyPackages.aarch64-darwin = outputs.legacyPackages.aarch64-darwin; }"
        )


class TestSelectSystemMatrices:
    @staticmethod
    def job(attr, system):
        return {
            "attr": attr,
            "name": attr or "no packages to build",
            "system": system,
            "runs_on": {"labels": ["ubuntu-slim"]},
        }

    def test_picks_the_system_and_ignores_placeholders(self):
        packages = {
            "x86_64_linux": {
                "include": [self.job("legacyPackages.x86_64-linux.a", "x86_64-linux")]
            },
            "aarch64_linux": {"include": [self.job("", "aarch64-linux")]},
        }
        checks = {
            "x86_64_linux": {"include": [self.job("", "x86_64-linux")]},
            "aarch64_linux": {"include": [self.job("", "aarch64-linux")]},
        }
        pkgs, chks, others = select_system_matrices(packages, checks, "x86_64-linux")
        assert pkgs == packages["x86_64_linux"]
        assert chks == checks["x86_64_linux"]
        assert others == []

    def test_reports_jobs_for_other_systems(self):
        packages = {
            "x86_64_linux": {"include": [self.job("", "x86_64-linux")]},
            "aarch64_linux": {
                "include": [self.job("legacyPackages.x86_64-linux.b", "aarch64-linux")]
            },
        }
        checks = {
            "x86_64_linux": {"include": [self.job("", "x86_64-linux")]},
            "aarch64_linux": {"include": [self.job("", "aarch64-linux")]},
        }
        _, _, others = select_system_matrices(packages, checks, "x86_64-linux")
        assert others == ["aarch64-linux"]


class TestWaitsForOtherJobs:
    def pkg(self, drv: str, needed: list[str]) -> NixEvalJobsOutput:
        return {
            "attr": "legacyPackages.x86_64-linux.a",
            "attrPath": ["legacyPackages", "x86_64-linux", "a"],
            "cacheStatus": "notBuilt",
            "drvPath": drv,
            "name": "a",
            "system": "x86_64-linux",
            "neededBuilds": needed,
        }

    def test_leaf_package(self):
        # Only needs itself, which is how nix-eval-jobs lists a package with no unbuilt inputs.
        assert not waits_for_other_jobs(self.pkg("/a.drv", ["/a.drv"]), {"/a.drv"})

    def test_depends_on_matrix_job(self):
        assert waits_for_other_jobs(
            self.pkg("/b.drv", ["/a.drv", "/b.drv"]), {"/a.drv", "/b.drv"}
        )

    def test_depends_on_build_outside_matrix(self):
        assert not waits_for_other_jobs(
            self.pkg("/b.drv", ["/dep.drv", "/b.drv"]), {"/b.drv"}
        )

    def test_missing_needed_builds(self):
        pkg = self.pkg("/b.drv", [])
        del pkg["neededBuilds"]
        assert not waits_for_other_jobs(pkg, {"/b.drv"})
