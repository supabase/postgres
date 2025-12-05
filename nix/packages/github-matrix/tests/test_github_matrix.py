#!/usr/bin/env python3

import pytest

from github_matrix import (
    NixEvalJobsOutput,
    get_runner_for_package,
    is_extension_pkg,
    is_kvm_pkg,
    is_large_pkg,
    sort_pkgs_by_closures,
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


class TestIsKvmPkg:
    def test_kvm_package(self):
        pkg: NixEvalJobsOutput = {
            "attr": "packages.x86_64-linux.vm-test",
            "attrPath": ["packages", "x86_64-linux", "vm-test"],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/test.drv",
            "name": "vm-test",
            "system": "x86_64-linux",
            "requiredSystemFeatures": ["kvm"],
        }
        assert is_kvm_pkg(pkg) is True

    def test_non_kvm_package(self):
        pkg: NixEvalJobsOutput = {
            "attr": "packages.x86_64-linux.psql_15",
            "attrPath": ["packages", "x86_64-linux", "psql_15"],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/test.drv",
            "name": "postgresql-16.0",
            "system": "x86_64-linux",
        }
        assert is_kvm_pkg(pkg) is False


class TestGetRunnerForPackage:
    def test_kvm_package_x86_64_linux(self):
        pkg: NixEvalJobsOutput = {
            "attr": "packages.x86_64-linux.vm-test",
            "attrPath": ["packages", "x86_64-linux", "vm-test"],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/test.drv",
            "name": "vm-test",
            "system": "x86_64-linux",
            "requiredSystemFeatures": ["kvm"],
        }
        with pytest.raises(
            ValueError,
            match=r"No self-hosted with kvm support available for system: x86_64-linux",
        ):
            get_runner_for_package(pkg)

    def test_kvm_package_aarch64_linux(self):
        pkg: NixEvalJobsOutput = {
            "attr": "packages.aarch64-linux.vm-test",
            "attrPath": ["packages", "aarch64-linux", "vm-test"],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/test.drv",
            "name": "vm-test",
            "system": "aarch64-linux",
            "requiredSystemFeatures": ["kvm"],
        }
        result = get_runner_for_package(pkg)
        assert result == {
            "group": "self-hosted-runners-nix",
            "labels": ["aarch64-linux"],
        }

    def test_large_package_x86_64_linux(self):
        pkg: NixEvalJobsOutput = {
            "attr": "legacyPackages.x86_64-linux.psql_15.exts.postgis",
            "attrPath": [
                "legacyPackages",
                "x86_64-linux",
                "psql_15",
                "exts",
                "postgis",
            ],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/test.drv",
            "name": "postgis",
            "system": "x86_64-linux",
            "requiredSystemFeatures": ["big-parallel"],
        }
        result = get_runner_for_package(pkg)
        assert result == {"labels": ["blacksmith-32vcpu-ubuntu-2404"]}

    def test_large_package_aarch64_linux(self):
        pkg: NixEvalJobsOutput = {
            "attr": "legacyPackages.aarch64-linux.psql_15.exts.pg_graphql",
            "attrPath": [
                "legacyPackages",
                "aarch64-linux",
                "psql_15",
                "exts",
                "pg_graphql",
            ],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/test.drv",
            "name": "pg_graphql",
            "system": "aarch64-linux",
            "requiredSystemFeatures": ["big-parallel"],
        }
        result = get_runner_for_package(pkg)
        assert result == {"labels": ["blacksmith-32vcpu-ubuntu-2404-arm"]}

    def test_darwin_package(self):
        pkg: NixEvalJobsOutput = {
            "attr": "legacyPackages.aarch64-darwin.psql_15",
            "attrPath": ["legacyPackages", "aarch64-darwin", "psql_15"],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/test.drv",
            "name": "postgresql-16.0",
            "system": "aarch64-darwin",
        }
        result = get_runner_for_package(pkg)
        assert result == {
            "group": "self-hosted-runners-nix",
            "labels": ["aarch64-darwin"],
        }

    def test_default_x86_64_linux(self):
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
        result = get_runner_for_package(pkg)
        assert result == {"labels": ["blacksmith-8vcpu-ubuntu-2404"]}

    def test_default_aarch64_linux(self):
        pkg: NixEvalJobsOutput = {
            "attr": "legacyPackages.aarch64-linux.psql_15.exts.pg_cron",
            "attrPath": [
                "legacyPackages",
                "aarch64-linux",
                "psql_15",
                "exts",
                "pg_cron",
            ],
            "cacheStatus": "notBuilt",
            "drvPath": "/nix/store/test.drv",
            "name": "pg_cron",
            "system": "aarch64-linux",
        }
        result = get_runner_for_package(pkg)
        assert result == {"labels": ["blacksmith-8vcpu-ubuntu-2404-arm"]}


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
