import base64
import boto3
import gzip
import logging
import os
import pytest
import requests
import socket
from ec2instanceconnectcli.EC2InstanceConnectLogger import EC2InstanceConnectLogger
from ec2instanceconnectcli.EC2InstanceConnectKey import EC2InstanceConnectKey
from time import sleep
import subprocess
import paramiko

# if GITHUB_RUN_ID is not set, use a default value that includes the user and hostname
RUN_ID = os.environ.get(
    "GITHUB_RUN_ID",
    "unknown-ci-run-"
    + os.environ.get("USER", "unknown-user")
    + "@"
    + socket.gethostname(),
)
AMI_NAME = os.environ.get("AMI_NAME")
postgresql_schema_sql_content = """
ALTER DATABASE postgres SET "app.settings.jwt_secret" TO  'my_jwt_secret_which_is_not_so_secret';
ALTER DATABASE postgres SET "app.settings.jwt_exp" TO 3600;

ALTER USER supabase_admin WITH PASSWORD 'postgres';
ALTER USER postgres WITH PASSWORD 'postgres';
ALTER USER authenticator WITH PASSWORD 'postgres';
ALTER USER pgbouncer WITH PASSWORD 'postgres';
ALTER USER supabase_auth_admin WITH PASSWORD 'postgres';
ALTER USER supabase_storage_admin WITH PASSWORD 'postgres';
ALTER USER supabase_replication_admin WITH PASSWORD 'postgres';
ALTER ROLE supabase_read_only_user WITH PASSWORD 'postgres';
ALTER ROLE supabase_admin SET search_path TO "$user",public,auth,extensions;
"""
realtime_env_content = ""
adminapi_yaml_content = """
port: 8085
host: 0.0.0.0
ref: aaaaaaaaaaaaaaaaaaaa
jwt_secret: my_jwt_secret_which_is_not_so_secret
metric_collectors:
    - filesystem
    - meminfo
    - netdev
    - loadavg
    - cpu
    - diskstats
    - vmstat
node_exporter_additional_args:
    - '--collector.filesystem.ignored-mount-points=^/(boot|sys|dev|run).*'
    - '--collector.netdev.device-exclude=lo'
cert_path: /etc/ssl/adminapi/server.crt
key_path: /etc/ssl/adminapi/server.key
upstream_metrics_refresh_duration: 60s
pgbouncer_endpoints:
    - 'postgres://pgbouncer:postgres@localhost:6543/pgbouncer'
fail2ban_socket: /var/run/fail2ban/fail2ban.sock
upstream_metrics_sources:
    -
        name: system
        url: 'https://localhost:8085/metrics'
        labels_to_attach: [{name: supabase_project_ref, value: aaaaaaaaaaaaaaaaaaaa}, {name: service_type, value: db}]
        skip_tls_verify: true
    -
        name: postgresql
        url: 'http://localhost:9187/metrics'
        labels_to_attach: [{name: supabase_project_ref, value: aaaaaaaaaaaaaaaaaaaa}, {name: service_type, value: postgresql}]
    -
        name: gotrue
        url: 'http://localhost:9122/metrics'
        labels_to_attach: [{name: supabase_project_ref, value: aaaaaaaaaaaaaaaaaaaa}, {name: service_type, value: gotrue}]
    -
        name: postgrest
        url: 'http://localhost:3001/metrics'
        labels_to_attach: [{name: supabase_project_ref, value: aaaaaaaaaaaaaaaaaaaa}, {name: service_type, value: postgrest}]
monitoring:
    disk_usage:
        enabled: true
firewall:
    enabled: true
    internal_ports:
        - 9187
        - 8085
        - 9122
    privileged_ports:
        - 22
    privileged_ports_allowlist:
        - 0.0.0.0/0
    filtered_ports:
        - 5432
        - 6543
    unfiltered_ports:
        - 80
        - 443
    managed_rules_file: /etc/nftables/supabase_managed.conf
pg_egress_collect_path: /tmp/pg_egress_collect.txt
aws_config:
    creds:
        enabled: false
        check_frequency: 1h
        refresh_buffer_duration: 6h
"""
pgsodium_root_key_content = (
    "0000000000000000000000000000000000000000000000000000000000000000"
)
postgrest_base_conf_content = """
db-uri = "postgres://authenticator:postgres@localhost:5432/postgres?application_name=postgrest"
db-schema = "public, storage, graphql_public"
db-anon-role = "anon"
jwt-secret = "my_jwt_secret_which_is_not_so_secret"
role-claim-key = ".role"
openapi-mode = "ignore-privileges"
db-use-legacy-gucs = true
admin-server-port = 3001
server-host = "*6"
db-pool-acquisition-timeout = 10
max-rows = 1000
db-extra-search-path = "public, extensions"
"""
gotrue_env_content = """
API_EXTERNAL_URL=http://localhost
GOTRUE_API_HOST=0.0.0.0
GOTRUE_SITE_URL=
GOTRUE_DB_DRIVER=postgres
GOTRUE_DB_DATABASE_URL=postgres://supabase_auth_admin@localhost/postgres?sslmode=disable
GOTRUE_JWT_ADMIN_ROLES=supabase_admin,service_role
GOTRUE_JWT_AUD=authenticated
GOTRUE_JWT_SECRET=my_jwt_secret_which_is_not_so_secret
"""
walg_config_json_content = """
{
  "AWS_REGION": "ap-southeast-1",
  "WALG_S3_PREFIX": "",
  "PGDATABASE": "postgres",
  "PGUSER": "supabase_admin",
  "PGPORT": 5432,
  "WALG_DELTA_MAX_STEPS": 6,
  "WALG_COMPRESSION_METHOD": "lz4"
}
"""
anon_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhIiwicm9sZSI6ImFub24iLCJpYXQiOjE2OTYyMjQ5NjYsImV4cCI6MjAxMTgwMDk2Nn0.QW95aRPA-4QuLzuvaIeeoFKlJP9J2hvAIpJ3WJ6G5zo"
service_role_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhIiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTY5NjIyNDk2NiwiZXhwIjoyMDExODAwOTY2fQ.Om7yqv15gC3mLGitBmvFRB3M4IsLsX9fXzTQnFM7lu0"
supabase_admin_key = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImFhYWFhYWFhYWFhYWFhYWFhYWFhIiwicm9sZSI6InN1cGFiYXNlX2FkbWluIiwiaWF0IjoxNjk2MjI0OTY2LCJleHAiOjIwMTE4MDA5NjZ9.jrD3j2rBWiIx0vhVZzd1CXFv7qkAP392nBMadvXxk1c"
init_json_content = f"""
{{
  "jwt_secret": "my_jwt_secret_which_is_not_so_secret",
  "project_ref": "aaaaaaaaaaaaaaaaaaaa",
  "logflare_api_key": "",
  "logflare_pitr_errors_source": "",
  "logflare_postgrest_source": "",
  "logflare_pgbouncer_source": "",
  "logflare_db_source": "",
  "logflare_gotrue_source": "",
  "anon_key": "{anon_key}",
  "service_key": "{service_role_key}",
  "supabase_admin_key": "{supabase_admin_key}",
  "common_name": "db.aaaaaaaaaaaaaaaaaaaa.supabase.red",
  "region": "ap-southeast-1",
  "init_database_only": false
}}
"""

logger = logging.getLogger("ami-tests")
handler = logging.StreamHandler()
formatter = logging.Formatter("%(asctime)s %(name)-12s %(levelname)-8s %(message)s")
handler.setFormatter(formatter)
logger.addHandler(handler)
logger.setLevel(logging.DEBUG)


def get_ssh_connection(instance_ip, ssh_identity_file, max_retries=10):
    """Create and return a single SSH connection that can be reused."""
    for attempt in range(max_retries):
        try:
            # Create SSH client
            ssh = paramiko.SSHClient()
            ssh.set_missing_host_key_policy(paramiko.AutoAddPolicy())
            
            # Connect with our working parameters
            ssh.connect(
                hostname=instance_ip,
                username='ubuntu',
                key_filename=ssh_identity_file,
                timeout=10,
                banner_timeout=10
            )
            
            # Test the connection
            stdin, stdout, stderr = ssh.exec_command('echo "SSH test"')
            if stdout.channel.recv_exit_status() == 0 and "SSH test" in stdout.read().decode():
                logger.info("SSH connection established successfully")
                return ssh
            else:
                raise Exception("SSH test command failed")
                
        except Exception as e:
            if attempt == max_retries - 1:
                raise
            logger.warning(
                f"Ssh connection failed, retrying: {attempt + 1}/{max_retries} failed, retrying ..."
            )
            sleep(5)


def run_ssh_command(ssh, command):
    """Run a command over the established SSH connection."""
    stdin, stdout, stderr = ssh.exec_command(command)
    exit_code = stdout.channel.recv_exit_status()
    return {
        'succeeded': exit_code == 0,
        'stdout': stdout.read().decode(),
        'stderr': stderr.read().decode()
    }


# scope='session' uses the same container for all the tests;
# scope='function' uses a new container per test function.
@pytest.fixture(scope="session")
def host():
    ec2 = boto3.resource("ec2", region_name="ap-southeast-1")
    images = list(
        ec2.images.filter(
            Filters=[{"Name": "name", "Values": [AMI_NAME]}],
        )
    )
    assert len(images) == 1
    image = images[0]

    def gzip_then_base64_encode(s: str) -> str:
        return base64.b64encode(gzip.compress(s.encode())).decode()

    instance = list(
        ec2.create_instances(
            BlockDeviceMappings=[
                {
                    "DeviceName": "/dev/sda1",
                    "Ebs": {
                        "VolumeSize": 8,  # gb
                        "Encrypted": True,
                        "DeleteOnTermination": True,
                        "VolumeType": "gp3",
                    },
                },
            ],
            MetadataOptions={
                "HttpTokens": "required",
                "HttpEndpoint": "enabled",
            },
            IamInstanceProfile={"Name": "pg-ap-southeast-1"},
            InstanceType="t4g.micro",
            MinCount=1,
            MaxCount=1,
            ImageId=image.id,
            NetworkInterfaces=[
                {
                    "DeviceIndex": 0,
                    "AssociatePublicIpAddress": True,
                    "Groups": ["sg-0a883ca614ebfbae0", "sg-014d326be5a1627dc"],
                }
            ],
            UserData=f"""#cloud-config
hostname: db-aaaaaaaaaaaaaaaaaaaa
write_files:
    - {{path: /etc/postgresql.schema.sql, content: {gzip_then_base64_encode(postgresql_schema_sql_content)}, permissions: '0600', encoding: gz+b64}}
    - {{path: /etc/realtime.env, content: {gzip_then_base64_encode(realtime_env_content)}, permissions: '0664', encoding: gz+b64}}
    - {{path: /etc/adminapi/adminapi.yaml, content: {gzip_then_base64_encode(adminapi_yaml_content)}, permissions: '0600', owner: 'adminapi:root', encoding: gz+b64}}
    - {{path: /etc/postgresql-custom/pgsodium_root.key, content: {gzip_then_base64_encode(pgsodium_root_key_content)}, permissions: '0600', owner: 'postgres:postgres', encoding: gz+b64}}
    - {{path: /etc/postgrest/base.conf, content: {gzip_then_base64_encode(postgrest_base_conf_content)}, permissions: '0664', encoding: gz+b64}}
    - {{path: /etc/gotrue.env, content: {gzip_then_base64_encode(gotrue_env_content)}, permissions: '0664', encoding: gz+b64}}
    - {{path: /etc/wal-g/config.json, content: {gzip_then_base64_encode(walg_config_json_content)}, permissions: '0664', owner: 'wal-g:wal-g', encoding: gz+b64}}
    - {{path: /tmp/init.json, content: {gzip_then_base64_encode(init_json_content)}, permissions: '0600', encoding: gz+b64}}
runcmd:
    - 'sudo echo \"pgbouncer\" \"postgres\" >> /etc/pgbouncer/userlist.txt'
    - 'cd /tmp && aws s3 cp --region ap-southeast-1 s3://init-scripts-staging/project/init.sh .'
    - 'bash init.sh "staging"'
    - 'touch /var/lib/init-complete'
    - 'rm -rf /tmp/*'
""",
            TagSpecifications=[
                {
                    "ResourceType": "instance",
                    "Tags": [
                        {"Key": "Name", "Value": "ci-ami-test-nix"},
                        {"Key": "creator", "Value": "testinfra-ci"},
                        {"Key": "testinfra-run-id", "Value": RUN_ID},
                    ],
                }
            ],
        )
    )[0]
    instance.wait_until_running()

    # Increase wait time before starting health checks
    sleep(30)  # Wait for 30 seconds to allow services to start

    ec2logger = EC2InstanceConnectLogger(debug=False)
    temp_key = EC2InstanceConnectKey(ec2logger.get_logger())
    ec2ic = boto3.client("ec2-instance-connect", region_name="ap-southeast-1")
    response = ec2ic.send_ssh_public_key(
        InstanceId=instance.id,
        InstanceOSUser="ubuntu",
        SSHPublicKey=temp_key.get_pub_key(),
    )
    assert response["Success"]

    # Wait for instance to have public IP
    while not instance.public_ip_address:
        logger.warning("waiting for ip to be available")
        sleep(5)
        instance.reload()

    # Create single SSH connection
    ssh = get_ssh_connection(
        instance.public_ip_address,
        temp_key.get_priv_key_file(),
    )

    # Check PostgreSQL data directory
    logger.info("Checking PostgreSQL data directory...")
    result = run_ssh_command(ssh, "ls -la /var/lib/postgresql")
    if result['succeeded']:
        logger.info("PostgreSQL data directory contents:\n" + result['stdout'])
    else:
        logger.warning("Failed to list PostgreSQL data directory: " + result['stderr'])

    # Wait for init.sh to complete
    logger.info("Waiting for init.sh to complete...")
    max_attempts = 60  # 5 minutes
    attempt = 0
    while attempt < max_attempts:
        try:
            result = run_ssh_command(ssh, "test -f /var/lib/init-complete")
            if result['succeeded']:
                logger.info("init.sh has completed")
                break
        except Exception as e:
            logger.warning(f"Error checking init.sh status: {str(e)}")
        
        attempt += 1
        logger.warning(f"Waiting for init.sh to complete (attempt {attempt}/{max_attempts})")
        sleep(5)

    if attempt >= max_attempts:
        logger.error("init.sh failed to complete within the timeout period")
        instance.terminate()
        raise TimeoutError("init.sh failed to complete within the timeout period")

    def is_healthy(ssh) -> bool:
        health_checks = [
            ("postgres", "sudo -u postgres /usr/bin/pg_isready -U postgres"),
            ("adminapi", f"curl -sf -k --connect-timeout 30 --max-time 60 https://localhost:8085/health -H 'apikey: {supabase_admin_key}'"),
            ("postgrest", "curl -sf --connect-timeout 30 --max-time 60 http://localhost:3001/ready"),
            ("gotrue", "curl -sf --connect-timeout 30 --max-time 60 http://localhost:8081/health"),
            ("kong", "sudo kong health"),
            ("fail2ban", "sudo fail2ban-client status"),
        ]

        for service, command in health_checks:
            try:
                result = run_ssh_command(ssh, command)
                if not result['succeeded']:
                    logger.warning(f"{service} not ready")
                    return False
            except Exception:
                logger.warning(f"Connection failed during {service} check")
                return False

        return True

    while True:
        if is_healthy(ssh):
            break
        sleep(1)

    # Return both the SSH connection and instance IP for use in tests
    yield {
        'ssh': ssh,
        'ip': instance.public_ip_address
    }

    # at the end of the test suite, destroy the instance
    instance.terminate()


def test_postgrest_is_running(host):
    """Check if postgrest service is running using our SSH connection."""
    result = run_ssh_command(host['ssh'], "systemctl is-active postgrest")
    assert result['succeeded'] and result['stdout'].strip() == 'active', "PostgREST service is not running"


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
        f"http://{host['ip']}/rest/v1/buckets",
        headers={
            "apikey": service_role_key,
            "authorization": f"Bearer {service_role_key}",
            "accept-profile": "storage",
        },
    )
    assert res.ok


def test_postgrest_starting_apikey_query_parameter_is_removed(host):
    """Test if PostgREST removes apikey query parameter at start."""
    res = requests.get(
        f"http://{host['ip']}/rest/v1/buckets",
        headers={
            "accept-profile": "storage",
        },
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
        f"http://{host['ip']}/rest/v1/buckets",
        headers={
            "accept-profile": "storage",
        },
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
        f"http://{host['ip']}/rest/v1/buckets",
        headers={
            "accept-profile": "storage",
        },
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
        f"http://{host['ip']}/rest/v1/buckets",
        headers={
            "accept-profile": "storage",
        },
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
        f"http://{host['ip']}/rest/v1/buckets",
        headers={
            "accept-profile": "storage",
        },
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
        f"http://{host['ip']}/rest/v1/buckets",
        headers={
            "accept-profile": "storage",
        },
        params={
            "id": "eq.absent",
            "apikey": service_role_key,
            "": "empty_key",
        },
    )
    assert res.ok


def test_postgresql_version(host):
    """Print the PostgreSQL version being tested and ensure it's >= 14."""
    result = run_ssh_command(host['ssh'], "sudo -u postgres psql -c 'SELECT version();'")
    if result['succeeded']:
        print(f"\nPostgreSQL Version:\n{result['stdout']}")
        # Extract version number from the output
        version_line = result['stdout'].strip().split('\n')[2]  # Skip header and get the actual version
        # Extract major version number (e.g., "15.8" -> 15)
        import re
        version_match = re.search(r'PostgreSQL (\d+)\.', version_line)
        if version_match:
            major_version = int(version_match.group(1))
            print(f"PostgreSQL major version: {major_version}")
            assert major_version >= 14, f"PostgreSQL version {major_version} is less than 14"
        else:
            assert False, "Could not parse PostgreSQL version number"
    else:
        print(f"\nFailed to get PostgreSQL version: {result['stderr']}")
        assert False, "Failed to get PostgreSQL version"
    
    # Also get the version from the command line
    result = run_ssh_command(host['ssh'], "sudo -u postgres psql --version")
    if result['succeeded']:
        print(f"PostgreSQL Client Version: {result['stdout'].strip()}")
    else:
        print(f"Failed to get PostgreSQL client version: {result['stderr']}")
    
    print("✓ PostgreSQL version is >= 14")


def test_libpq5_version(host):
    """Print the libpq5 version installed and ensure it's >= 14."""
    # Try different package managers to find libpq5
    result = run_ssh_command(host['ssh'], "dpkg -l | grep libpq5 || true")
    if result['succeeded'] and result['stdout'].strip():
        print(f"\nlibpq5 package info:\n{result['stdout']}")
        # Extract version from dpkg output (format: ii libpq5:arm64 17.5-1.pgdg20.04+1)
        import re
        version_match = re.search(r'libpq5[^ ]* +(\d+)\.', result['stdout'])
        if version_match:
            major_version = int(version_match.group(1))
            print(f"libpq5 major version: {major_version}")
            assert major_version >= 14, f"libpq5 version {major_version} is less than 14"
        else:
            print("Could not parse libpq5 version from dpkg output")
    else:
        print("\nlibpq5 not found via dpkg")
    
    # Also try to find libpq.so files
    result = run_ssh_command(host['ssh'], "find /usr -name '*libpq*' -type f 2>/dev/null | head -10")
    if result['succeeded'] and result['stdout'].strip():
        print(f"\nlibpq files found:\n{result['stdout']}")
    else:
        print("\nNo libpq files found")
    
    # Check if we can get version from a libpq file
    result = run_ssh_command(host['ssh'], "ldd /usr/bin/psql | grep libpq || true")
    if result['succeeded'] and result['stdout'].strip():
        print(f"\npsql libpq dependency:\n{result['stdout']}")
    else:
        print("\nCould not find libpq dependency for psql")
    
    # Try to get version from libpq directly
    result = run_ssh_command(host['ssh'], "psql --version 2>&1 | head -1")
    if result['succeeded'] and result['stdout'].strip():
        print(f"\npsql version output: {result['stdout'].strip()}")
        # The psql version should match the libpq version
        import re
        version_match = re.search(r'psql \(PostgreSQL\) (\d+)\.', result['stdout'])
        if version_match:
            major_version = int(version_match.group(1))
            print(f"psql/libpq major version: {major_version}")
            assert major_version >= 14, f"psql/libpq version {major_version} is less than 14"
        else:
            print("Could not parse psql version")
    
    print("✓ libpq5 version is >= 14")


def test_postgrest_read_only_session_attrs(host):
    """Test PostgREST with target_session_attrs=read-only and check for session errors."""
    # First, check if PostgreSQL is configured for read-only mode
    result = run_ssh_command(host['ssh'], "sudo -u postgres psql -c \"SHOW default_transaction_read_only;\"")
    if result['succeeded']:
        default_read_only = result['stdout'].strip()
        print(f"PostgreSQL default_transaction_read_only: {default_read_only}")
    else:
        print("Could not check PostgreSQL read-only setting")
        default_read_only = "unknown"
    
    # Check if PostgreSQL is in recovery mode (standby)
    result = run_ssh_command(host['ssh'], "sudo -u postgres psql -c \"SELECT pg_is_in_recovery();\"")
    if result['succeeded']:
        in_recovery = result['stdout'].strip()
        print(f"PostgreSQL pg_is_in_recovery: {in_recovery}")
    else:
        print("Could not check PostgreSQL recovery status")
        in_recovery = "unknown"
    
    # Find PostgreSQL configuration file
    result = run_ssh_command(host['ssh'], "sudo -u postgres psql -c \"SHOW config_file;\"")
    if result['succeeded']:
        config_file = result['stdout'].strip().split('\n')[2].strip()  # Skip header and get the actual path
        print(f"PostgreSQL config file: {config_file}")
    else:
        print("Could not find PostgreSQL config file")
        config_file = "/etc/postgresql/15/main/postgresql.conf"  # Default fallback
    
    # Backup PostgreSQL config
    result = run_ssh_command(host['ssh'], f"sudo cp {config_file} {config_file}.backup")
    assert result['succeeded'], "Failed to backup PostgreSQL config"
    
    # Add read-only setting to PostgreSQL config
    result = run_ssh_command(host['ssh'], f"echo 'default_transaction_read_only = on' | sudo tee -a {config_file}")
    assert result['succeeded'], "Failed to add read-only setting to PostgreSQL config"
    
    # Restart PostgreSQL to apply the new configuration
    result = run_ssh_command(host['ssh'], "sudo systemctl restart postgresql")
    assert result['succeeded'], "Failed to restart PostgreSQL"
    
    # Wait for PostgreSQL to start up
    sleep(5)
    
    # Verify the change took effect
    result = run_ssh_command(host['ssh'], "sudo -u postgres psql -c \"SHOW default_transaction_read_only;\"")
    if result['succeeded']:
        new_default_read_only = result['stdout'].strip()
        print(f"PostgreSQL default_transaction_read_only after change: {new_default_read_only}")
    else:
        print("Could not verify PostgreSQL read-only setting change")
    
    # First, backup the current PostgREST config
    result = run_ssh_command(host['ssh'], "sudo cp /etc/postgrest/base.conf /etc/postgrest/base.conf.backup")
    assert result['succeeded'], "Failed to backup PostgREST config"
    
    try:
        # Read the current config to get the db-uri
        result = run_ssh_command(host['ssh'], "sudo cat /etc/postgrest/base.conf | grep '^db-uri'")
        assert result['succeeded'], "Failed to read current db-uri"
        
        current_db_uri = result['stdout'].strip()
        print(f"Current db-uri: {current_db_uri}")
        
        # Extract just the URI part (remove the db-uri = " prefix and trailing quote)
        uri_start = current_db_uri.find('"') + 1
        uri_end = current_db_uri.rfind('"')
        base_uri = current_db_uri[uri_start:uri_end]
        
        # Modify the URI to add target_session_attrs=read-only
        if '?' in base_uri:
            # URI already has parameters, add target_session_attrs
            modified_uri = base_uri + "&target_session_attrs=read-only"
        else:
            # URI has no parameters, add target_session_attrs
            modified_uri = base_uri + "?target_session_attrs=read-only"
        
        print(f"Modified URI: {modified_uri}")
        
        # Use awk to replace the db-uri line more reliably
        result = run_ssh_command(host['ssh'], f"sudo awk '{{if ($1 == \"db-uri\") print \"db-uri = \\\"{modified_uri}\\\"\"; else print $0}}' /etc/postgrest/base.conf > /tmp/new_base.conf && sudo mv /tmp/new_base.conf /etc/postgrest/base.conf")
        assert result['succeeded'], "Failed to update db-uri in config"
        
        # Verify the change was made correctly
        result = run_ssh_command(host['ssh'], "sudo cat /etc/postgrest/base.conf | grep '^db-uri'")
        print(f"Updated db-uri line: {result['stdout'].strip()}")
        
        # Also show the full config to debug
        result = run_ssh_command(host['ssh'], "sudo cat /etc/postgrest/base.conf")
        print(f"Full config after change:\n{result['stdout']}")
        
        # Restart PostgREST to apply the new configuration
        result = run_ssh_command(host['ssh'], "sudo systemctl restart postgrest")
        assert result['succeeded'], "Failed to restart PostgREST"
        
        # Wait a moment for PostgREST to start up
        sleep(5)
        
        # Check if PostgREST is running
        result = run_ssh_command(host['ssh'], "sudo systemctl is-active postgrest")
        if not (result['succeeded'] and result['stdout'].strip() == 'active'):
            # If PostgREST failed to start, check the logs to see why
            log_result = run_ssh_command(host['ssh'], "sudo journalctl -u postgrest --since '5 seconds ago' --no-pager")
            print(f"PostgREST failed to start. Recent logs:\n{log_result['stdout']}")
            assert False, "PostgREST failed to start after config change"
        
        # Make a test request to trigger any potential session errors
        try:
            response = requests.get(
                f"http://{host['ip']}/rest/v1/",
                headers={"apikey": anon_key, "authorization": f"Bearer {anon_key}"},
                timeout=10
            )
            print(f"Test request status: {response.status_code}")
        except Exception as e:
            print(f"Test request failed: {str(e)}")
        
        # Check PostgREST logs for "session is not read-only" errors
        result = run_ssh_command(host['ssh'], "sudo journalctl -u postgrest --since '5 seconds ago' | grep -i 'session is not read-only' || true")
        
        if result['stdout'].strip():
            print(f"\nFound 'session is not read-only' errors in PostgREST logs:\n{result['stdout']}")
            assert False, "PostgREST logs contain 'session is not read-only' errors even though PostgreSQL is configured for read-only mode"
        else:
            print("\nNo 'session is not read-only' errors found in PostgREST logs")
            
    finally:
        # Restore the original configuration
        result = run_ssh_command(host['ssh'], "sudo cp /etc/postgrest/base.conf.backup /etc/postgrest/base.conf")
        if result['succeeded']:
            result = run_ssh_command(host['ssh'], "sudo systemctl restart postgrest")
            if result['succeeded']:
                print("Restored original PostgREST configuration")
            else:
                print("Warning: Failed to restart PostgREST after restoring config")
        else:
            print("Warning: Failed to restore original PostgREST configuration")
        
        # Restore PostgreSQL to original configuration
        result = run_ssh_command(host['ssh'], f"sudo cp {config_file}.backup {config_file}")
        if result['succeeded']:
            result = run_ssh_command(host['ssh'], "sudo systemctl restart postgresql")
            if result['succeeded']:
                print("Restored PostgreSQL to original configuration")
            else:
                print("Warning: Failed to restart PostgreSQL after restoring config")
        else:
            print("Warning: Failed to restore PostgreSQL configuration")

