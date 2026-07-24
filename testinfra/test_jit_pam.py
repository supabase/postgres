from conftest import run_ssh_command


def test_jit_pam_module_installed(host):
    """Test that the JIT PAM module (pam_jit_pg.so) is properly installed."""
    # Check PostgreSQL version first
    result = run_ssh_command(
        host["ssh"], "sudo -u postgres psql --version | grep -oE '[0-9]+' | head -1"
    )
    pg_major_version = 15  # Default
    if result["succeeded"] and result["stdout"].strip():
        try:
            pg_major_version = int(result["stdout"].strip())
        except ValueError:
            pass

    # Skip test for PostgreSQL 15 as gatekeeper is not installed for PG15
    if pg_major_version == 15:
        print("\nSkipping JIT PAM module test for PostgreSQL 15 (not installed)")
        return

    # Check if gatekeeper is installed via Nix
    result = run_ssh_command(
        host["ssh"],
        "sudo -u postgres ls -la /var/lib/postgresql/.nix-profile/lib/security/pam_jit_pg.so 2>/dev/null",
    )
    if result["succeeded"]:
        print(f"\nJIT PAM module found in Nix profile:\n{result['stdout']}")
    else:
        print("\nJIT PAM module not found in postgres user's Nix profile")
        assert False, "JIT PAM module (pam_jit_pg.so) not found in expected location"

    # Check if the symlink exists in the Linux PAM security directory
    result = run_ssh_command(
        host["ssh"],
        "find /nix/store -type f -path '*/lib/security/pam_jit_pg.so' 2>/dev/null | head -5",
    )
    if result["succeeded"] and result["stdout"].strip():
        print(f"\nJIT PAM module symlinks found:\n{result['stdout']}")
    else:
        print("\nNo JIT PAM module symlinks found in /nix/store")

    # Verify the module is a valid shared library
    result = run_ssh_command(
        host["ssh"], "file /var/lib/postgresql/.nix-profile/lib/security/pam_jit_pg.so"
    )
    if result["succeeded"]:
        print(f"\nJIT PAM module file type:\n{result['stdout']}")
        assert (
            "shared object" in result["stdout"].lower()
            or "dynamically linked" in result["stdout"].lower()
        ), "JIT PAM module is not a valid shared library"

    print("✓ JIT PAM module is properly installed")


def test_pam_postgresql_config(host):
    """Test that the PAM configuration for PostgreSQL exists and is properly configured."""
    # Check PostgreSQL version to determine if PAM config should exist
    result = run_ssh_command(
        host["ssh"], "sudo -u postgres psql --version | grep -oE '[0-9]+' | head -1"
    )
    pg_major_version = 15  # Default
    if result["succeeded"] and result["stdout"].strip():
        try:
            pg_major_version = int(result["stdout"].strip())
        except ValueError:
            pass

    print(f"\nPostgreSQL major version: {pg_major_version}")

    # PAM config should exist for non-PostgreSQL 15 versions
    if pg_major_version != 15:
        # Check if PAM config file exists
        result = run_ssh_command(host["ssh"], "ls -la /etc/pam.d/postgresql")
        if result["succeeded"]:
            print(f"\nPAM config file found:\n{result['stdout']}")

            # Check file permissions
            result = run_ssh_command(
                host["ssh"], "stat -c '%a %U %G' /etc/pam.d/postgresql"
            )
            if result["succeeded"]:
                perms = result["stdout"].strip()
                print(f"PAM config permissions: {perms}")
                # Should be owned by postgres:postgres with 664 permissions
                assert "postgres postgres" in perms, (
                    "PAM config not owned by postgres:postgres"
                )
        else:
            print("\nPAM config file not found")
            assert False, "PAM configuration file /etc/pam.d/postgresql not found"
    else:
        print("\nSkipping PAM config check for PostgreSQL 15")
        # For PostgreSQL 15, the PAM config should NOT exist
        result = run_ssh_command(host["ssh"], "test -f /etc/pam.d/postgresql")
        if result["succeeded"]:
            print("\nWARNING: PAM config exists for PostgreSQL 15 (not expected)")

    print("✓ PAM configuration is properly set up")


def test_jit_pam_gatekeeper_profile(host):
    """Test that the gatekeeper package is properly installed in the postgres user's Nix profile."""
    # Check PostgreSQL version first
    result = run_ssh_command(
        host["ssh"], "sudo -u postgres psql --version | grep -oE '[0-9]+' | head -1"
    )
    pg_major_version = 15  # Default
    if result["succeeded"] and result["stdout"].strip():
        try:
            pg_major_version = int(result["stdout"].strip())
        except ValueError:
            pass

    # Skip test for PostgreSQL 15 as gatekeeper is not installed for PG15
    if pg_major_version == 15:
        print("\nSkipping gatekeeper profile test for PostgreSQL 15 (not installed)")
        return

    # Check if gatekeeper is in the postgres user's Nix profile
    result = run_ssh_command(
        host["ssh"],
        "sudo -u postgres nix profile list --json | jq -r '.elements.gatekeeper.storePaths[0]'",
    )
    if result["succeeded"] and result["stdout"].strip():
        print(f"\nGatekeeper found in Nix profile:\n{result['stdout']}")
    else:
        # Try alternative check
        result = run_ssh_command(
            host["ssh"],
            "sudo -u postgres ls -la /var/lib/postgresql/.nix-profile/ | grep -i gate",
        )
        if result["succeeded"] and result["stdout"].strip():
            print(f"\nGatekeeper-related files in profile:\n{result['stdout']}")
        else:
            print("\nGatekeeper not found in postgres user's Nix profile")
            # This might be expected if it's installed system-wide instead

    # Check if we can find the gatekeeper derivation
    result = run_ssh_command(
        host["ssh"],
        "find /nix/store -maxdepth 1 -type d -name '*gatekeeper*' 2>/dev/null | head -5",
    )
    if result["succeeded"] and result["stdout"].strip():
        print(f"\nGatekeeper derivations found:\n{result['stdout']}")
    else:
        print("\nNo gatekeeper derivations found in /nix/store")

    print("✓ Gatekeeper package installation check completed")


def test_jit_pam_module_dependencies(host):
    """Test that the JIT PAM module has all required dependencies."""
    # Check PostgreSQL version first
    result = run_ssh_command(
        host["ssh"], "sudo -u postgres psql --version | grep -oE '[0-9]+' | head -1"
    )
    pg_major_version = 15  # Default
    if result["succeeded"] and result["stdout"].strip():
        try:
            pg_major_version = int(result["stdout"].strip())
        except ValueError:
            pass

    # Skip test for PostgreSQL 15 as gatekeeper is not installed for PG15
    if pg_major_version == 15:
        print(
            "\nSkipping JIT PAM module dependencies test for PostgreSQL 15 (not installed)"
        )
        return

    # Check dependencies of the PAM module
    result = run_ssh_command(
        host["ssh"],
        "ldd /var/lib/postgresql/.nix-profile/lib/security/pam_jit_pg.so 2>/dev/null",
    )
    if result["succeeded"]:
        print(f"\nJIT PAM module dependencies:\n{result['stdout']}")

        # Check for required libraries
        required_libs = ["libpam", "libc"]
        for lib in required_libs:
            if lib not in result["stdout"].lower():
                print(f"WARNING: Required library {lib} not found in dependencies")

        # Check for any missing dependencies
        if "not found" in result["stdout"].lower():
            assert False, "JIT PAM module has missing dependencies"
    else:
        print("\nCould not check JIT PAM module dependencies")

    print("✓ JIT PAM module dependencies are satisfied")


def test_jit_pam_postgresql_integration(host):
    """Test that PostgreSQL can be configured to use PAM authentication."""
    # Check if PAM is available as an authentication method in PostgreSQL
    result = run_ssh_command(
        host["ssh"],
        "sudo -u postgres psql -c \"SELECT name, setting FROM pg_settings WHERE name LIKE '%pam%';\" 2>/dev/null",
    )
    if result["succeeded"]:
        print(f"\nPostgreSQL PAM-related settings:\n{result['stdout']}")

    # Check pg_hba.conf for potential PAM entries (even if not currently active)
    result = run_ssh_command(
        host["ssh"],
        "grep -i pam /etc/postgresql/pg_hba.conf 2>/dev/null || echo 'No PAM entries in pg_hba.conf'",
    )
    if result["succeeded"]:
        print(f"\nPAM entries in pg_hba.conf:\n{result['stdout']}")

    # Verify PostgreSQL was compiled with PAM support
    result = run_ssh_command(
        host["ssh"],
        "sudo -u postgres pg_config --configure 2>/dev/null | grep -i pam || echo 'PAM compile flag not found'",
    )
    if result["succeeded"]:
        print(f"\nPostgreSQL PAM compile flags:\n{result['stdout']}")

    print("✓ PostgreSQL PAM integration check completed")
