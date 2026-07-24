from time import sleep
import requests
from conftest import anon_key, run_ssh_command, service_role_key


def test_postgrest_is_running(host):
    """Check if postgrest service is running using our SSH connection."""
    result = run_ssh_command(host["ssh"], "systemctl is-active postgrest")
    assert result["succeeded"] and result["stdout"].strip() == "active", (
        "PostgREST service is not running"
    )


def test_postgrest_responds_to_requests(host):
    """Test if PostgREST responds to requests."""
    res = requests.get(
        f"http://{host['ip']}/rest/v1/",
        headers={
            "apikey": anon_key,
            "authorization": f"Bearer {anon_key}",
        },
    )
    assert res.ok


def test_postgrest_can_connect_to_db(host):
    """Test if PostgREST can connect to the database."""
    res = requests.get(
        f"http://{host['ip']}/rest-admin/v1/ready",
        headers={
            "apikey": service_role_key,
            "authorization": f"Bearer {service_role_key}",
        },
    )
    assert res.ok


def test_postgrest_starting_apikey_query_parameter_is_removed(host):
    """Test if PostgREST removes apikey query parameter at start."""
    res = requests.get(
        f"http://{host['ip']}/rest/v1/",
        params={
            "apikey": service_role_key,
            "id": "eq.absent",
            "name": "eq.absent",
        },
    )
    assert res.ok


def test_postgrest_middle_apikey_query_parameter_is_removed(host):
    """Test if PostgREST removes apikey query parameter in middle."""
    res = requests.get(
        f"http://{host['ip']}/rest/v1/",
        params={
            "id": "eq.absent",
            "apikey": service_role_key,
            "name": "eq.absent",
        },
    )
    assert res.ok


def test_postgrest_ending_apikey_query_parameter_is_removed(host):
    """Test if PostgREST removes apikey query parameter at end."""
    res = requests.get(
        f"http://{host['ip']}/rest/v1/",
        params={
            "id": "eq.absent",
            "name": "eq.absent",
            "apikey": service_role_key,
        },
    )
    assert res.ok


def test_postgrest_starting_empty_key_query_parameter_is_removed(host):
    """Test if PostgREST removes empty key query parameter at start."""
    res = requests.get(
        f"http://{host['ip']}/rest/v1/",
        params={
            "": "empty_key",
            "id": "eq.absent",
            "apikey": service_role_key,
        },
    )
    assert res.ok


def test_postgrest_middle_empty_key_query_parameter_is_removed(host):
    """Test if PostgREST removes empty key query parameter in middle."""
    res = requests.get(
        f"http://{host['ip']}/rest/v1/",
        params={
            "apikey": service_role_key,
            "": "empty_key",
            "id": "eq.absent",
        },
    )
    assert res.ok


def test_postgrest_ending_empty_key_query_parameter_is_removed(host):
    """Test if PostgREST removes empty key query parameter at end."""
    res = requests.get(
        f"http://{host['ip']}/rest/v1/",
        params={
            "id": "eq.absent",
            "apikey": service_role_key,
            "": "empty_key",
        },
    )
    assert res.ok
def test_postgrest_read_only_session_attrs(host):
    """Test PostgREST with target_session_attrs=read-only and check for session errors."""
    # First, check if PostgreSQL is configured for read-only mode
    result = run_ssh_command(
        host["ssh"], 'sudo -u postgres psql -c "SHOW default_transaction_read_only;"'
    )
    if result["succeeded"]:
        default_read_only = result["stdout"].strip()
        print(f"PostgreSQL default_transaction_read_only: {default_read_only}")
    else:
        print("Could not check PostgreSQL read-only setting")
        default_read_only = "unknown"

    # Check if PostgreSQL is in recovery mode (standby)
    result = run_ssh_command(
        host["ssh"], 'sudo -u postgres psql -c "SELECT pg_is_in_recovery();"'
    )
    if result["succeeded"]:
        in_recovery = result["stdout"].strip()
        print(f"PostgreSQL pg_is_in_recovery: {in_recovery}")
    else:
        print("Could not check PostgreSQL recovery status")
        in_recovery = "unknown"

    # Find PostgreSQL configuration file
    result = run_ssh_command(
        host["ssh"], 'sudo -u postgres psql -c "SHOW config_file;"'
    )
    if result["succeeded"]:
        config_file = (
            result["stdout"].strip().split("\n")[2].strip()
        )  # Skip header and get the actual path
        print(f"PostgreSQL config file: {config_file}")
    else:
        print("Could not find PostgreSQL config file")
        config_file = "/etc/postgresql/15/main/postgresql.conf"  # Default fallback

    # Backup PostgreSQL config
    result = run_ssh_command(host["ssh"], f"sudo cp {config_file} {config_file}.backup")
    assert result["succeeded"], "Failed to backup PostgreSQL config"

    # Add read-only setting to PostgreSQL config
    result = run_ssh_command(
        host["ssh"],
        f"echo 'default_transaction_read_only = on' | sudo tee -a {config_file}",
    )
    assert result["succeeded"], "Failed to add read-only setting to PostgreSQL config"

    # Restart PostgreSQL to apply the new configuration
    result = run_ssh_command(host["ssh"], "sudo systemctl restart postgresql")
    assert result["succeeded"], "Failed to restart PostgreSQL"

    # Wait for PostgreSQL to start up
    sleep(5)

    # Verify the change took effect
    result = run_ssh_command(
        host["ssh"], 'sudo -u postgres psql -c "SHOW default_transaction_read_only;"'
    )
    if result["succeeded"]:
        new_default_read_only = result["stdout"].strip()
        print(
            f"PostgreSQL default_transaction_read_only after change: {new_default_read_only}"
        )
    else:
        print("Could not verify PostgreSQL read-only setting change")

    # First, backup the current PostgREST config
    result = run_ssh_command(
        host["ssh"], "sudo cp /etc/postgrest/base.conf /etc/postgrest/base.conf.backup"
    )
    assert result["succeeded"], "Failed to backup PostgREST config"

    try:
        # Read the current config to get the db-uri
        result = run_ssh_command(
            host["ssh"], "sudo cat /etc/postgrest/base.conf | grep '^db-uri'"
        )
        assert result["succeeded"], "Failed to read current db-uri"

        current_db_uri = result["stdout"].strip()
        print(f"Current db-uri: {current_db_uri}")

        # Extract just the URI part (remove the db-uri = " prefix and trailing quote)
        uri_start = current_db_uri.find('"') + 1
        uri_end = current_db_uri.rfind('"')
        base_uri = current_db_uri[uri_start:uri_end]

        # Modify the URI to add target_session_attrs=read-only
        if "?" in base_uri:
            # URI already has parameters, add target_session_attrs
            modified_uri = base_uri + "&target_session_attrs=read-only"
        else:
            # URI has no parameters, add target_session_attrs
            modified_uri = base_uri + "?target_session_attrs=read-only"

        print(f"Modified URI: {modified_uri}")

        # Use awk to replace the db-uri line more reliably
        result = run_ssh_command(
            host["ssh"],
            f'sudo awk \'{{if ($1 == "db-uri") print "db-uri = \\"{modified_uri}\\""; else print $0}}\' /etc/postgrest/base.conf > /tmp/new_base.conf && sudo mv /tmp/new_base.conf /etc/postgrest/base.conf',
        )
        assert result["succeeded"], "Failed to update db-uri in config"

        # Verify the change was made correctly
        result = run_ssh_command(
            host["ssh"], "sudo cat /etc/postgrest/base.conf | grep '^db-uri'"
        )
        print(f"Updated db-uri line: {result['stdout'].strip()}")

        # Also show the full config to debug
        result = run_ssh_command(host["ssh"], "sudo cat /etc/postgrest/base.conf")
        print(f"Full config after change:\n{result['stdout']}")

        # Restart PostgREST to apply the new configuration
        result = run_ssh_command(host["ssh"], "sudo systemctl restart postgrest")
        assert result["succeeded"], "Failed to restart PostgREST"

        # Wait a moment for PostgREST to start up
        sleep(5)

        # Check if PostgREST is running
        result = run_ssh_command(host["ssh"], "sudo systemctl is-active postgrest")
        if not (result["succeeded"] and result["stdout"].strip() == "active"):
            # If PostgREST failed to start, check the logs to see why
            log_result = run_ssh_command(
                host["ssh"],
                "sudo journalctl -u postgrest --since '5 seconds ago' --no-pager",
            )
            print(f"PostgREST failed to start. Recent logs:\n{log_result['stdout']}")
            assert False, "PostgREST failed to start after config change"

        # Make a test request to trigger any potential session errors
        try:
            response = requests.get(
                f"http://{host['ip']}/rest/v1/",
                headers={"apikey": anon_key, "authorization": f"Bearer {anon_key}"},
                timeout=10,
            )
            print(f"Test request status: {response.status_code}")
        except Exception as e:
            print(f"Test request failed: {str(e)}")

        # Check PostgREST logs for "session is not read-only" errors
        result = run_ssh_command(
            host["ssh"],
            "sudo journalctl -u postgrest --since '5 seconds ago' | grep -i 'session is not read-only' || true",
        )

        if result["stdout"].strip():
            print(
                f"\nFound 'session is not read-only' errors in PostgREST logs:\n{result['stdout']}"
            )
            assert False, (
                "PostgREST logs contain 'session is not read-only' errors even though PostgreSQL is configured for read-only mode"
            )
        else:
            print("\nNo 'session is not read-only' errors found in PostgREST logs")

    finally:
        # Restore the original configuration
        result = run_ssh_command(
            host["ssh"],
            "sudo cp /etc/postgrest/base.conf.backup /etc/postgrest/base.conf",
        )
        if result["succeeded"]:
            result = run_ssh_command(host["ssh"], "sudo systemctl restart postgrest")
            if result["succeeded"]:
                print("Restored original PostgREST configuration")
            else:
                print("Warning: Failed to restart PostgREST after restoring config")
        else:
            print("Warning: Failed to restore original PostgREST configuration")

        # Restore PostgreSQL to original configuration
        result = run_ssh_command(
            host["ssh"], f"sudo cp {config_file}.backup {config_file}"
        )
        if result["succeeded"]:
            result = run_ssh_command(host["ssh"], "sudo systemctl restart postgresql")
            if result["succeeded"]:
                print("Restored PostgreSQL to original configuration")
            else:
                print("Warning: Failed to restart PostgreSQL after restoring config")
        else:
            print("Warning: Failed to restore PostgreSQL configuration")
