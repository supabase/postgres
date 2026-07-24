from conftest import run_ssh_command


def test_apparmor_postgresql_service_uses_profile(host):
    """Verify the PostgreSQL systemd service is running under the sbpostgres AppArmor profile."""
    result = run_ssh_command(
        host["ssh"], "systemctl show postgresql | grep -i apparmor"
    )
    assert result["succeeded"], (
        f"Could not find AppArmor info in postgresql service status.\n"
        f"stderr: {result['stderr']}"
    )
    assert "sbpostgres" in result["stdout"], (
        f"Expected 'sbpostgres' in postgresql AppArmor status but got:\n{result['stdout']}"
    )


def test_apparmor_sbpostgres_profile_enforced(host):
    """Verify the sbpostgres AppArmor profile is loaded and in enforce mode."""
    import json

    result = run_ssh_command(host["ssh"], "sudo aa-status --json")
    assert result["succeeded"], f"aa-status failed: {result['stderr']}"
    status = json.loads(result["stdout"])
    enforced = status.get("profiles", {})
    assert "sbpostgres" in enforced, "sbpostgres profile not found in AppArmor"
    assert enforced["sbpostgres"] == "enforce", (
        f"sbpostgres profile is not in enforce mode: {enforced['sbpostgres']}"
    )


def test_apparmor_blocks_disallowed_shell_commands(host):
    """Verify AppArmor's postgres_shell sub-profile blocks execution of
    commands not on the allowlist (e.g. /usr/bin/id).

    COPY TO PROGRAM causes postgres to fork /bin/sh, which transitions to the
    postgres_shell sub-profile via the 'Pix -> postgres_shell' rule. /usr/bin/id
    is not on the allowlist so AppArmor denies the exec, and PostgreSQL surfaces
    this as 'command not executable'.
    """
    result = run_ssh_command(
        host["ssh"],
        "sudo -u postgres psql -U supabase_admin -h localhost -d postgres -c \"COPY (SELECT 1) TO PROGRAM '/usr/bin/id';\" 2>&1 || true",
    )
    combined = result["stdout"] + result["stderr"]
    assert "command not executable" in combined, (
        f"Expected AppArmor to block /usr/bin/id with 'command not executable' "
        f"but got:\nstdout: {result['stdout']}\nstderr: {result['stderr']}"
    )


def test_apparmor_permits_allowlisted_commands(host):
    """Verify allowlisted commands are not blocked by the postgres_shell profile.

    /usr/bin/cat is explicitly listed as 'ix' in postgres_shell with a canonical
    path (avoiding the /bin -> /usr/bin symlink issue on Ubuntu 22.04+), and
    writes only to the pipe so no file-write permissions are needed.
    """
    result = run_ssh_command(
        host["ssh"],
        "sudo -u postgres psql -U supabase_admin -h localhost -d postgres -c \"COPY (SELECT 1) TO PROGRAM '/usr/bin/cat';\"",
    )
    assert result["succeeded"], (
        f"AppArmor unexpectedly blocked /usr/bin/cat.\n"
        f"stdout: {result['stdout']}\nstderr: {result['stderr']}"
    )


def test_apparmor_allows_basic_sql_and_extensions(host):
    """Verify basic SQL and extension availability are unaffected by AppArmor."""
    result = run_ssh_command(
        host["ssh"],
        "sudo -u postgres psql -U supabase_admin -h localhost -d postgres -c "
        "\"SELECT name FROM pg_available_extensions WHERE name IN ('pgcrypto', 'pg_stat_statements') ORDER BY name;\"",
    )
    assert result["succeeded"], (
        f"SQL query failed under AppArmor.\nstdout: {result['stdout']}\nstderr: {result['stderr']}"
    )
    assert "pgcrypto" in result["stdout"], (
        "pgcrypto extension not available under AppArmor"
    )
    assert "pg_stat_statements" in result["stdout"], (
        "pg_stat_statements extension not available under AppArmor"
    )


def test_apparmor_allows_pg_dump(host):
    """Verify pg_dump executes from postgres_shell under AppArmor.

    /usr/bin/pg_dump is explicitly listed as 'ix' in postgres_shell.
    """
    result = run_ssh_command(
        host["ssh"],
        "sudo -u postgres psql -U supabase_admin -h localhost -d postgres -c "
        "\"COPY (SELECT 1) TO PROGRAM '/usr/bin/pg_dump --version';\"",
    )
    assert result["succeeded"], (
        f"pg_dump was blocked by AppArmor.\n"
        f"stdout: {result['stdout']}\nstderr: {result['stderr']}"
    )


def test_apparmor_allows_walg(host):
    """Verify wal-g-2 can be executed under the sbpostgres AppArmor profile.

    /nix/store/*/bin/wal-g-2 is listed as 'ix' in postgres_shell. We locate the
    binary at runtime since the Nix store hash is not known ahead of time.
    """
    find_result = run_ssh_command(
        host["ssh"],
        "find /nix/store -maxdepth 3 -name 'wal-g-2' -type f 2>/dev/null | head -1",
    )
    walg_path = find_result["stdout"].strip()
    if not walg_path:
        print("wal-g-2 not found in Nix store, skipping")
        return

    result = run_ssh_command(
        host["ssh"],
        f"sudo -u postgres psql -U supabase_admin -h localhost -d postgres -c "
        f"\"COPY (SELECT 1) TO PROGRAM '{walg_path} --version';\"",
    )
    assert result["succeeded"], (
        f"wal-g-2 was blocked by AppArmor.\n"
        f"stdout: {result['stdout']}\nstderr: {result['stderr']}"
    )


def test_apparmor_denies_access_to_sensitive_paths(host):
    """Verify postgres_shell deny rules block access to sensitive system paths.

    The profile has 'deny /var/lib/supabase/** rwx', 'deny /opt/saltstack/** rwx',
    and 'deny /etc/salt/** rwx'. Files are created world-readable so that the
    only reason cat fails is AppArmor, not OS file permissions.
    """
    denied_paths = [
        "/var/lib/supabase",
        "/opt/saltstack",
        "/etc/salt",
    ]
    for base in denied_paths:
        run_ssh_command(
            host["ssh"],
            f"sudo mkdir -p {base} && echo 'restricted' | sudo tee {base}/apparmor_test.txt > /dev/null "
            f"&& sudo chmod 644 {base}/apparmor_test.txt",
        )

    for base in denied_paths:
        test_file = f"{base}/apparmor_test.txt"
        result = run_ssh_command(
            host["ssh"],
            f"sudo -u postgres psql -U supabase_admin -h localhost -d postgres -c "
            f"\"COPY (SELECT 1) TO PROGRAM '/usr/bin/cat {test_file}';\" 2>&1 || true",
        )
        combined = result["stdout"] + result["stderr"]
        assert (
            "failed" in combined.lower() or "child process exited" in combined.lower()
        ), (
            f"Expected AppArmor to deny access to {test_file} but the command appears "
            f"to have succeeded.\nstdout: {result['stdout']}\nstderr: {result['stderr']}"
        )
        print(f"Confirmed: access to {test_file} denied by AppArmor")
