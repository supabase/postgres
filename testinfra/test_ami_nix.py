import base64
import boto3
import gzip
import logging
import os
import pytest
import requests
import socket
import testinfra
from ec2instanceconnectcli.EC2InstanceConnectLogger import EC2InstanceConnectLogger
from ec2instanceconnectcli.EC2InstanceConnectKey import EC2InstanceConnectKey
from time import sleep

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

    ec2logger = EC2InstanceConnectLogger(debug=False)
    temp_key = EC2InstanceConnectKey(ec2logger.get_logger())
    ec2ic = boto3.client("ec2-instance-connect", region_name="ap-southeast-1")
    response = ec2ic.send_ssh_public_key(
        InstanceId=instance.id,
        InstanceOSUser="ubuntu",
        SSHPublicKey=temp_key.get_pub_key(),
    )
    assert response["Success"]

    # instance doesn't have public ip yet
    while not instance.public_ip_address:
        logger.warning("waiting for ip to be available")
        sleep(5)
        instance.reload()

    while True:
        sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        if sock.connect_ex((instance.public_ip_address, 22)) == 0:
            break
        else:
            logger.warning("waiting for ssh to be available")
            sleep(10)

    def get_ssh_connection(instance_ip, ssh_identity_file, max_retries=10):
        for attempt in range(max_retries):
            try:
                return testinfra.get_host(
                    f"paramiko://ubuntu@{instance_ip}?timeout=60",
                    ssh_identity_file=ssh_identity_file,
                )
            except Exception as e:
                if attempt == max_retries - 1:
                    raise
                logger.warning(
                    f"Ssh connection failed, retrying: {attempt + 1}/{max_retries} failed, retrying ..."
                )
                sleep(5)

    host = get_ssh_connection(
        # paramiko is an ssh backend
        instance.public_ip_address,
        temp_key.get_priv_key_file(),
    )

    def is_healthy(host, instance_ip, ssh_identity_file) -> bool:
        health_checks = [
            (
                "postgres",
                lambda h: h.run("sudo -u postgres /usr/bin/pg_isready -U postgres"),
            ),
            (
                "adminapi",
                lambda h: h.run(
                    f"curl -sf -k --connect-timeout 30 --max-time 60 https://localhost:8085/health -H 'apikey: {supabase_admin_key}'"
                ),
            ),
            (
                "postgrest",
                lambda h: h.run(
                    "curl -sf --connect-timeout 30 --max-time 60 http://localhost:3001/ready"
                ),
            ),
            (
                "gotrue",
                lambda h: h.run(
                    "curl -sf --connect-timeout 30 --max-time 60 http://localhost:8081/health"
                ),
            ),
            ("kong", lambda h: h.run("sudo kong health")),
            ("fail2ban", lambda h: h.run("sudo fail2ban-client status")),
        ]

        for service, check in health_checks:
            try:
                cmd = check(host)
                if cmd.failed is True:
                    logger.warning(f"{service} not ready")
                    return False
            except Exception:
                logger.warning(
                    f"Connection failed during {service} check, attempting reconnect..."
                )
                host = get_ssh_connection(instance_ip, ssh_identity_file)
                return False

        return True

    while True:
        if is_healthy(
            host=host,
            instance_ip=instance.public_ip_address,
            ssh_identity_file=temp_key.get_priv_key_file(),
        ):
            break
        sleep(1)

    # return a testinfra connection to the instance
    yield host

    # at the end of the test suite, destroy the instance
    instance.terminate()


def test_postgrest_is_running(host):
    postgrest = host.service("postgrest")
    assert postgrest.is_running


def test_postgrest_responds_to_requests(host):
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/",
        headers={
            "apikey": anon_key,
            "authorization": f"Bearer {anon_key}",
        },
    )
    assert res.ok


def test_postgrest_can_connect_to_db(host):
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
        headers={
            "apikey": service_role_key,
            "authorization": f"Bearer {service_role_key}",
            "accept-profile": "storage",
        },
    )
    assert res.ok


# There would be an error if the `apikey` query parameter isn't removed,
# since PostgREST treats query parameters as conditions.
#
# Worth testing since remove_apikey_query_parameters uses regexp instead
# of parsed query parameters.
def test_postgrest_starting_apikey_query_parameter_is_removed(host):
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
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
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
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
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
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


# There would be an error if the empty key query parameter isn't removed,
# since PostgREST treats empty key query parameters as malformed input.
#
# Worth testing since remove_apikey_and_empty_key_query_parameters uses regexp instead
# of parsed query parameters.
def test_postgrest_starting_empty_key_query_parameter_is_removed(host):
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
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
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
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
    res = requests.get(
        f"http://{host.backend.get_hostname()}/rest/v1/buckets",
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
