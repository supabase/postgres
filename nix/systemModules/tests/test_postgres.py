def test_postgres_directories(host):
    """Test that all required PostgreSQL directories are created with correct permissions"""
    directories = [
        ("/home/postgres", "755"),
        ("/var/log/postgresql", "755"),
        ("/var/lib/postgresql", "755"),
        ("/etc/postgresql", "775"),
        ("/etc/postgresql-custom", "775"),
        ("/data/pgdata", "750"),
        ("/usr/lib/postgresql", "755"),
    ]

    for directory, expected_mode in directories:
        dir_file = host.file(directory)
        assert dir_file.is_directory, f"Directory {directory} should exist"
        assert oct(dir_file.mode)[-3:] == expected_mode, (
            f"Directory {directory} should have mode {expected_mode}"
        )


def test_postgres_symlinks(host):
    """Test that PostgreSQL symlinks are created correctly"""
    symlinks = [
        "/var/lib/postgresql/data",
        "/usr/lib/postgresql/bin",
    ]

    for symlink in symlinks:
        link_file = host.file(symlink)
        assert link_file.is_symlink, f"File {symlink} should be a symlink"


def test_postgres_configuration_files(host):
    """Test that PostgreSQL configuration files exist and have correct permissions"""
    config_files = [
        ("/etc/postgresql/pg_hba.conf", "440"),
        ("/etc/postgresql/postgresql.conf", "440"),
    ]

    for config_file, expected_mode in config_files:
        file_obj = host.file(config_file)
        assert file_obj.is_file, f"Configuration file {config_file} should exist"
        if expected_mode:
            assert oct(file_obj.mode)[-3:] == expected_mode, (
                f"File {config_file} should have mode {expected_mode}"
            )


def test_postgres_package_installed(host):
    """Test that PostgreSQL package is installed and available"""
    # Check if postgres binaries are available
    postgres_binaries = [
        "postgres",
        "psql",
        "createdb",
        "dropdb",
        "pg_dump",
        "pg_restore",
    ]

    for binary in postgres_binaries:
        result = host.run(f"bash --login -c 'which {binary}'")
        assert result.rc == 0, f"PostgreSQL binary {binary} should be available in PATH"


def test_postgres_environment_profile(host):
    """Test that PostgreSQL environment variables are set in profile"""
    profile_file = host.file("/etc/profile.d/postgresql.sh")
    assert profile_file.is_file, "PostgreSQL profile script should exist"

    expected_vars = ["LANG", "LANGUAGE", "LC_ALL", "LC_CTYPE"]

    for var in expected_vars:
        result = host.run(f"bash --login -c 'echo ${var}'")
        assert result.stdout.strip() != "", f"Environment variable {var} should be set"


def test_postgres_systemd_target(host):
    """Test that PostgreSQL systemd target is configured"""
    result = host.run("systemctl cat postgresql.target")
    assert result.rc == 0, "PostgreSQL systemd target should exist"

    target_content = result.stdout
    assert "Requires=postgresql.service postgresql-setup.service" in target_content

    system_manager_link = host.file(
        "/etc/systemd/system/system-manager.target.wants/postgresql.target"
    )
    assert system_manager_link.is_symlink, "System manager should have a symlink"
    assert "postgresql.target" in system_manager_link.linked_to, (
        "System manager should have a symlink to postgresql.target"
    )


def test_postgres_data_directory_symlink(host):
    """Test that the data directory symlink points to the correct location"""
    data_link = host.file("/var/lib/postgresql/data")
    assert data_link.is_symlink, "Data directory should be a symlink"
    assert data_link.linked_to == "/data/pgdata", (
        "Data directory should link to /data/pgdata"
    )


def test_usr_lib_postgresql(host):
    """Test that the bin directory symlink exists"""
    for path in ["bin", "share", "lib"]:
        dir_path = f"/usr/lib/postgresql/{path}"
        dir_file = host.file(dir_path)
        assert dir_file.is_symlink, f"Symlink {dir_path} should exist"


def test_postgres_configuration_content(host):
    """Test that PostgreSQL configuration contains expected settings"""
    config_file = host.file("/etc/postgresql/postgresql.conf")
    assert config_file.is_file, "PostgreSQL configuration file should exist"

    content = config_file.content_string
    assert "hba_file = '/etc/postgresql/pg_hba.conf'" in content
    assert "log_destination = 'stderr'" in content


def test_postgres_hba_configuration(host):
    """Test that pg_hba.conf file exists and is readable"""
    hba_file = host.file("/etc/postgresql/pg_hba.conf")
    assert hba_file.is_file, "pg_hba.conf file should exist"
    assert hba_file.user == "postgres", "pg_hba.conf should be owned by root"
    assert hba_file.group == "postgres", "pg_hba.conf should be owned by root group"


def test_postgres_directory_ownership(host):
    """Test that PostgreSQL directories have correct ownership"""
    directories = [
        "/home/postgres",
        "/var/log/postgresql",
        "/var/lib/postgresql",
        "/etc/postgresql",
        "/etc/postgresql-custom",
        "/data/pgdata",
    ]

    for directory in directories:
        dir_file = host.file(directory)
        assert dir_file.user == "postgres", (
            f"Directory {directory} should be owned by root"
        )
        assert dir_file.group == "postgres", (
            f"Directory {directory} should be owned by root group"
        )


def test_postgres_configuration(host):
    """Test that PostgreSQL configuration file exists and has correct permissions"""
    config_file = host.file("/etc/postgresql/postgresql.conf")
    assert config_file.is_file, "PostgreSQL configuration file should exist"
    assert oct(config_file.mode)[-3:] == "440", (
        "PostgreSQL configuration file should have mode 440"
    )
    assert config_file.user == "postgres", (
        "PostgreSQL configuration file should be owned by postgres"
    )
    assert config_file.group == "postgres", (
        "PostgreSQL configuration file should be owned by postgres group"
    )

    # db_user_namespace doesn't exist in postgres >= 16
    assert not config_file.contains("db_user_namespace")

def test_locales(host):
    installed_locales = host.run("localectl list-locales").stdout
    assert "C.UTF-8" in installed_locales, "C.UTF-8 locale should be installed"
    assert "en_US.UTF-8" in installed_locales, "en_US.UTF-8 locale should be installed"

def test_postgres_service_running(host):
    assert host.service("postgresql.service").is_valid
    assert host.service("postgresql.service").is_running

    required_logs = [
        "Using language tag \"en-US\" for ICU locale \"en_US.UTF-8\"",
        "locale provider:   icu",
        "default collation: en-US",
        "LC_COLLATE:  en_US.UTF-8",
        "LC_CTYPE:    en_US.UTF-8",
        "LC_MESSAGES: en_US.UTF-8",
        "LC_MONETARY: en_US.UTF-8",
        "LC_NUMERIC:  en_US.UTF-8",
        "vault primary server secret key loaded",
        "pg_cron scheduler started",
    ]
    logs = host.run("journalctl -u postgresql.service --no-pager").stdout
    for log in required_logs:
        assert log in logs, f"Log '{log}' should be present in PostgreSQL logs"
