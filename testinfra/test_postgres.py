from conftest import run_ssh_command


def test_postgresql_version(host):
    """Print the PostgreSQL version being tested and ensure it's >= 14."""
    result = run_ssh_command(
        host["ssh"], "sudo -u postgres psql -c 'SELECT version();'"
    )
    if result["succeeded"]:
        print(f"\nPostgreSQL Version:\n{result['stdout']}")
        # Extract version number from the output
        version_line = (
            result["stdout"].strip().split("\n")[2]
        )  # Skip header and get the actual version
        # Extract major version number (e.g., "15.8" -> 15)
        import re

        version_match = re.search(r"PostgreSQL (\d+)\.", version_line)
        if version_match:
            major_version = int(version_match.group(1))
            print(f"PostgreSQL major version: {major_version}")
            assert major_version >= 14, (
                f"PostgreSQL version {major_version} is less than 14"
            )
        else:
            assert False, "Could not parse PostgreSQL version number"
    else:
        print(f"\nFailed to get PostgreSQL version: {result['stderr']}")
        assert False, "Failed to get PostgreSQL version"

    # Also get the version from the command line
    result = run_ssh_command(host["ssh"], "sudo -u postgres psql --version")
    if result["succeeded"]:
        print(f"PostgreSQL Client Version: {result['stdout'].strip()}")
    else:
        print(f"Failed to get PostgreSQL client version: {result['stderr']}")

    print("✓ PostgreSQL version is >= 14")


def test_libpq5_version(host):
    """Print the libpq5 version installed and ensure it's >= 14."""
    # Try different package managers to find libpq5
    result = run_ssh_command(host["ssh"], "dpkg -l | grep libpq5 || true")
    if result["succeeded"] and result["stdout"].strip():
        print(f"\nlibpq5 package info:\n{result['stdout']}")
        # Extract version from dpkg output (format: ii libpq5:arm64 17.5-1.pgdg20.04+1)
        import re

        version_match = re.search(r"libpq5[^ ]* +(\d+)\.", result["stdout"])
        if version_match:
            major_version = int(version_match.group(1))
            print(f"libpq5 major version: {major_version}")
            assert major_version >= 14, (
                f"libpq5 version {major_version} is less than 14"
            )
        else:
            print("Could not parse libpq5 version from dpkg output")
    else:
        print("\nlibpq5 not found via dpkg")

    # Also try to find libpq.so files
    result = run_ssh_command(
        host["ssh"], "find /usr -name '*libpq*' -type f 2>/dev/null | head -10"
    )
    if result["succeeded"] and result["stdout"].strip():
        print(f"\nlibpq files found:\n{result['stdout']}")
    else:
        print("\nNo libpq files found")

    # Check if we can get version from a libpq file
    result = run_ssh_command(host["ssh"], "ldd /usr/bin/psql | grep libpq || true")
    if result["succeeded"] and result["stdout"].strip():
        print(f"\npsql libpq dependency:\n{result['stdout']}")
    else:
        print("\nCould not find libpq dependency for psql")

    # Try to get version from libpq directly
    result = run_ssh_command(host["ssh"], "psql --version 2>&1 | head -1")
    if result["succeeded"] and result["stdout"].strip():
        print(f"\npsql version output: {result['stdout'].strip()}")
        # The psql version should match the libpq version
        import re

        version_match = re.search(r"psql \(PostgreSQL\) (\d+)\.", result["stdout"])
        if version_match:
            major_version = int(version_match.group(1))
            print(f"psql/libpq major version: {major_version}")
            assert major_version >= 14, (
                f"psql/libpq version {major_version} is less than 14"
            )
        else:
            print("Could not parse psql version")

    print("✓ libpq5 version is >= 14")
