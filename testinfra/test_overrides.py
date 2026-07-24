from time import sleep
from conftest import run_ssh_command


def test_custom_overrides_take_precedence_over_generated_optimizations(host):
    """Verify CLI-managed PostgreSQL config overrides generated optimizations.

    postgresql.conf includes generated-optimizations.conf before
    custom-overrides.conf (both flat under /etc/postgresql-custom/, includes
    uncommented during the AMI build), so the custom override wins. include_dir
    conf.d comes after both, so anything in conf.d beats them by include order
    — a hosted incident happened when generated-optimizations.conf was placed
    in conf.d and silently overrode CLI-managed config. This test guards both
    sides of that contract: the flat-file precedence, and that the AMI ships
    no conf.d copy of generated-optimizations.conf.
    """
    ssh = host["ssh"]
    backup_dir = "/tmp/pg-config-precedence-test"
    custom_conf = "/etc/postgresql-custom/custom-overrides.conf"
    generated_conf = "/etc/postgresql-custom/generated-optimizations.conf"
    confd_generated_conf = "/etc/postgresql-custom/conf.d/generated-optimizations.conf"
    config_files = [custom_conf, generated_conf]

    confd_check = run_ssh_command(ssh, f"sudo test -e {confd_generated_conf}")
    assert not confd_check["succeeded"], (
        f"{confd_generated_conf} exists on the AMI; conf.d is included after "
        "custom-overrides.conf, so a generated-optimizations.conf there "
        "overrides CLI-managed config"
    )

    def assert_command_succeeded(result, action):
        assert result["succeeded"], (
            f"{action} failed.\nstdout: {result['stdout']}\nstderr: {result['stderr']}"
        )

    def backup_name(path):
        return path.strip("/").replace("/", "__")

    def backup_config_files():
        commands = [
            "set -eu",
            f"sudo rm -rf {backup_dir}",
            f"sudo mkdir -p {backup_dir}",
        ]
        for path in config_files:
            backup_path = f"{backup_dir}/{backup_name(path)}"
            commands.extend(
                [
                    f"if sudo test -e {path}; then",
                    f"    sudo cp -a {path} {backup_path}",
                    "else",
                    f"    sudo touch {backup_path}.missing",
                    "fi",
                ]
            )

        result = run_ssh_command(ssh, "\n".join(commands))
        assert_command_succeeded(result, "Backup PostgreSQL config files")

    def restore_config_files():
        commands = ["set -eu"]
        for path in config_files:
            backup_path = f"{backup_dir}/{backup_name(path)}"
            commands.extend(
                [
                    f"sudo mkdir -p $(dirname {path})",
                    f"if sudo test -f {backup_path}.missing; then",
                    f"    sudo rm -f {path}",
                    "else",
                    f"    sudo cp -a {backup_path} {path}",
                    "fi",
                ]
            )
        commands.append(f"sudo rm -rf {backup_dir}")
        return run_ssh_command(ssh, "\n".join(commands))

    def restart_postgresql(context):
        result = run_ssh_command(ssh, "sudo systemctl restart postgresql")
        assert_command_succeeded(result, context)
        sleep(5)

    def read_max_connections_source():
        result = run_ssh_command(
            ssh,
            "sudo -u postgres psql -X -v ON_ERROR_STOP=1 -t -A -F '|' "
            "-d postgres -c "
            '"SELECT setting, sourcefile '
            "FROM pg_settings WHERE name = 'max_connections';\"",
        )
        assert_command_succeeded(result, "Query max_connections setting")

        rows = [line.strip() for line in result["stdout"].splitlines() if line.strip()]
        assert len(rows) == 1, (
            f"Expected one max_connections row, got {len(rows)}:\n{result['stdout']}"
        )
        return rows[0].split("|", 1)

    backup_config_files()

    try:
        write_result = run_ssh_command(
            ssh,
            """
            set -eu
            CUSTOM_CONF=/etc/postgresql-custom/custom-overrides.conf
            GENERATED_CONF=/etc/postgresql-custom/generated-optimizations.conf

            printf '%s\n' 'max_connections = 111' |
                sudo tee "$GENERATED_CONF" > /dev/null
            printf '%s\n' 'max_connections = 112' |
                sudo tee "$CUSTOM_CONF" > /dev/null
            sudo chown postgres:postgres "$GENERATED_CONF" "$CUSTOM_CONF"
            sudo chmod 0664 "$GENERATED_CONF" "$CUSTOM_CONF"
            """,
        )
        assert_command_succeeded(
            write_result,
            "Write PostgreSQL precedence test config files",
        )

        restart_postgresql("Restart PostgreSQL with precedence test config")

        setting, sourcefile = read_max_connections_source()

        assert setting == "112", (
            "Expected custom-overrides.conf to win over generated optimizations "
            f"for max_connections, got setting={setting}, sourcefile={sourcefile}"
        )
        assert sourcefile == "/etc/postgresql-custom/custom-overrides.conf", (
            "Expected max_connections to come from custom-overrides.conf, "
            f"got sourcefile={sourcefile}"
        )
    finally:
        restore_result = restore_config_files()
        if not restore_result["succeeded"]:
            print(
                "Warning: Failed to restore PostgreSQL precedence test config files.\n"
                f"stdout: {restore_result['stdout']}\nstderr: {restore_result['stderr']}"
            )

        try:
            restart_postgresql("Restart PostgreSQL after precedence test restore")
            print("Restored PostgreSQL config files after precedence test")
        except AssertionError as error:
            print(
                "Warning: Failed to restart PostgreSQL after restoring "
                f"precedence test config.\n{error}"
            )
