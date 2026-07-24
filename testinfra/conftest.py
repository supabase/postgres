import base64
import gzip
import logging
import os
import socket
from pathlib import Path
from time import sleep

import boto3
import paramiko
import pytest
import requests
from ec2instanceconnectcli.EC2InstanceConnectKey import EC2InstanceConnectKey
from ec2instanceconnectcli.EC2InstanceConnectLogger import EC2InstanceConnectLogger

# if EXECUTION_ID is not set, use a default value that includes the user and hostname
RUN_ID = os.environ.get(
    "EXECUTION_ID",
    "unknown-ci-run-"
    + os.environ.get("USER", "unknown-user")
    + "@"
    + socket.gethostname(),
)
AMI_ID = os.environ.get("AMI_ID")
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
ALTER USER supabase_etl_admin WITH PASSWORD 'postgres';
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
db-schema = "public, graphql_public"
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


def load_expected_pgbouncer_version() -> str:
    repo_root = Path(__file__).resolve().parent.parent
    ansible_vars = repo_root / "ansible" / "vars.yml"
    if ansible_vars.exists():
        with ansible_vars.open() as f:
            for raw_line in f:
                line = raw_line.strip()
                if line.startswith("pgbouncer_release:"):
                    return line.split(":", 1)[1].strip().strip('"')

    nix_file = repo_root / "nix" / "pgbouncer.nix"
    if nix_file.exists():
        with nix_file.open() as f:
            for raw_line in f:
                line = raw_line.strip()
                if line.startswith("version ="):
                    value = line.split("=", 1)[1].strip()
                    return value.strip(";").strip('"')

    raise RuntimeError(
        "Could not determine expected PgBouncer version from configuration files"
    )


EXPECTED_PGBOUNCER_VERSION = load_expected_pgbouncer_version()
PGBOUNCER_BINARY = "/nix/var/nix/profiles/per-user/pgbouncer/profile/bin/pgbouncer"
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
                username="ubuntu",
                key_filename=ssh_identity_file,
                timeout=10,
                banner_timeout=10,
            )

            # Test the connection
            stdin, stdout, stderr = ssh.exec_command('echo "SSH test"')
            if (
                stdout.channel.recv_exit_status() == 0
                and "SSH test" in stdout.read().decode()
            ):
                logger.info("SSH connection established successfully")
                return ssh
            else:
                raise Exception("SSH test command failed")

        except Exception:
            if attempt == max_retries - 1:
                raise
            logger.warning(
                f"Ssh connection failed, retrying: {attempt + 1}/{max_retries} failed, retrying ..."
            )
            sleep(5)


def run_ssh_command(ssh, command, timeout=None):
    """Run a command over the established SSH connection."""
    stdin, stdout, stderr = ssh.exec_command(command, timeout=timeout)
    exit_code = stdout.channel.recv_exit_status()
    return {
        "succeeded": exit_code == 0,
        "stdout": stdout.read().decode(),
        "stderr": stderr.read().decode(),
    }


def upload_file_via_sftp(ssh, local_path, remote_path):
    """Upload a file to the remote host via SFTP."""
    sftp = ssh.open_sftp()
    try:
        sftp.put(local_path, remote_path)
        logger.info(f"Uploaded {local_path} to {remote_path}")
    finally:
        sftp.close()


# scope='session' uses the same container for all the tests;
# scope='function' uses a new container per test function.
@pytest.fixture(scope="session")
def host():
    ec2 = boto3.resource("ec2", region_name="ap-southeast-1")
    image = ec2.Image(AMI_ID)

    def gzip_then_base64_encode(s: str) -> str:
        return base64.b64encode(gzip.compress(s.encode())).decode()

    # Create temporary SSH key pair
    ec2logger = EC2InstanceConnectLogger(debug=False)
    temp_key = EC2InstanceConnectKey(ec2logger.get_logger())

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
            InstanceType="t4g.micro" if image.architecture == "arm64" else "t3.small",
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
users:
  - name: ubuntu
    ssh_authorized_keys:
      - {temp_key.get_pub_key()}
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
    if result["succeeded"]:
        logger.info("PostgreSQL data directory contents:\n" + result["stdout"])
    else:
        logger.warning("Failed to list PostgreSQL data directory: " + result["stderr"])

    # Wait for init.sh to complete
    logger.info("Waiting for init.sh to complete...")
    max_attempts = 60  # 5 minutes
    attempt = 0
    while attempt < max_attempts:
        try:
            result = run_ssh_command(ssh, "test -f /var/lib/init-complete", timeout=5)
            if result["succeeded"]:
                logger.info("init.sh has completed")
                break
        except Exception as e:
            logger.warning(f"Error checking init.sh status: {str(e)}")

        attempt += 1
        logger.warning(
            f"Waiting for init.sh to complete (attempt {attempt}/{max_attempts})"
        )
        sleep(5)

    if attempt >= max_attempts:
        logger.error("init.sh failed to complete within the timeout period")
        instance.terminate()
        raise TimeoutError("init.sh failed to complete within the timeout period")

    # Create auth-failures.csv file if it doesn't exist (required for fail2ban to start)
    # This matches what setup_fail2ban() does in the init script
    logger.info("Ensuring PostgreSQL auth-failures.csv exists...")
    result = run_ssh_command(
        ssh,
        "sudo mkdir -p /var/log/postgresql && sudo chown -R postgres:postgres /var/log/postgresql && sudo chmod 1775 /var/log/postgresql && sudo -u postgres touch /var/log/postgresql/auth-failures.csv && sudo chmod 0664 /var/log/postgresql/auth-failures.csv",
    )
    if not result["succeeded"]:
        logger.warning(f"Failed to create auth-failures.csv: {result['stderr']}")

    # Start fail2ban service before health checks
    logger.info("Starting fail2ban service...")
    result = run_ssh_command(ssh, "sudo systemctl start fail2ban.service")
    if not result["succeeded"]:
        logger.warning(f"Failed to start fail2ban: {result['stderr']}")
        # Check fail2ban logs for more details
        log_result = run_ssh_command(
            ssh, "sudo journalctl -u fail2ban -n 20 --no-pager"
        )
        if log_result["succeeded"]:
            logger.warning(f"fail2ban logs:\n{log_result['stdout']}")
    else:
        logger.info("fail2ban service started successfully")

    def is_healthy(ssh) -> bool:
        health_checks = [
            ("postgresql", "sudo -u postgres /usr/bin/pg_isready -U postgres"),
            (
                "adminapi",
                f"curl -sf -k --connect-timeout 30 --max-time 60 https://localhost:8085/health -H 'apikey: {supabase_admin_key}'",
            ),
            (
                "postgrest",
                "curl -sf --connect-timeout 30 --max-time 60 http://localhost:3001/ready",
            ),
            (
                "gotrue",
                "curl -sf --connect-timeout 30 --max-time 60 http://localhost:8081/health",
            ),
            ("kong", "sudo kong health"),
            ("fail2ban", "sudo fail2ban-client status"),
        ]

        for service, command in health_checks:
            try:
                result = run_ssh_command(ssh, command)
                if not result["succeeded"]:
                    info_text = ""
                    info_command = f"sudo journalctl -b -u {service} -n 20 --no-pager"
                    info_result = run_ssh_command(ssh, info_command)
                    if info_result["succeeded"]:
                        info_text = "\n" + info_result["stdout"].strip()

                    logger.warning(f"{service} not ready{info_text}")
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
    yield {"ssh": ssh, "ip": instance.public_ip_address}

    # at the end of the test suite, destroy the instance
    instance.terminate()
