from docker.models.containers import Container
from os import path
from time import sleep
from typing import cast
import docker
import pytest
import requests
import subprocess
import testinfra

all_in_one_image_tag = "supabase/all-in-one:testinfra"
all_in_one_envs = {
    "POSTGRES_PASSWORD": "postgres",
    "JWT_SECRET": "super-secret-jwt-token-with-at-least-32-characters-long",
    "ANON_KEY": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoiYW5vbiIsImlzcyI6InN1cGFiYXNlLWRlbW8iLCJpYXQiOjE2NDE3NjkyMDAsImV4cCI6MTc5OTUzNTYwMH0.F_rDxRTPE8OU83L_CNgEGXfmirMXmMMugT29Cvc8ygQ",
    "SERVICE_ROLE_KEY": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic2VydmljZV9yb2xlIiwiaXNzIjoic3VwYWJhc2UtZGVtbyIsImlhdCI6MTY0MTc2OTIwMCwiZXhwIjoxNzk5NTM1NjAwfQ.5z-pJI1qwZg1LE5yavGLqum65WOnnaaI5eZ3V00pLww",
    "ADMIN_API_KEY": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic3VwYWJhc2VfYWRtaW4iLCJpc3MiOiJzdXBhYmFzZS1kZW1vIiwiaWF0IjoxNjQxNzY5MjAwLCJleHAiOjE3OTk1MzU2MDB9.Y9mSNVuTw2TdfryoaqM5wySvwQemGGWfSe9ixcklVfM",
    "DATA_VOLUME_MOUNTPOINT": "/data",
    "MACHINE_TYPE": "shared_cpu_1x_512m",
    "PLATFORM_DEPLOYMENT": "true",
    "SWAP_DISABLED": "true",
    "AUTOSHUTDOWN_ENABLED": "true",
    "ENV_MAX_IDLE_TIME_MINUTES": "60",
    "PGDATA": "/var/lib/postgresql/data",
    "PGDATA_REAL": "/data/pgdata",
}

# TODO: spin up local Logflare for Vector tests.


# scope='session' uses the same container for all the tests;
# scope='function' uses a new container per test function.
@pytest.fixture(scope="session")
def host():
    # We build the image with the Docker CLI in path instead of using docker-py
    # (official Docker SDK for Python) because the latter doesn't use BuildKit,
    # so things like `ARG TARGETARCH` don't work:
    # - https://github.com/docker/docker-py/issues/2230
    # - https://docs.docker.com/engine/reference/builder/#automatic-platform-args-in-the-global-scope
    subprocess.check_call(
        [
            "docker",
            "buildx",
            "build",
            "--file",
            path.join(path.dirname(__file__), "../docker/all-in-one/Dockerfile"),
            "--load",
            "--tag",
            all_in_one_image_tag,
            path.join(path.dirname(__file__), ".."),
        ]
    )

    docker_client = docker.from_env()
    container = cast(
        Container,
        docker_client.containers.run(
            all_in_one_image_tag,
            detach=True,
            environment=all_in_one_envs,
            ports={
                "5432/tcp": 5432,
                "8000/tcp": 8000,
            },
        ),
    )

    def get_health(container: Container) -> str:
        inspect_results = docker_client.api.inspect_container(container.name)
        return inspect_results["State"]["Health"]["Status"]

    attempts = 0

    # containers might appear healthy but crash during bootstrap
    sleep(3)
    
    while True:
        health = get_health(container)
        if health == "healthy":
            break
        if attempts > 60 or health == "exited":
            # print container logs for debugging
            print(container.logs().decode("utf-8"))

            # write logs to file to be displayed in GHA output
            with open("testinfra-aio-container-logs.log", "w") as f:
                f.write(container.logs().decode("utf-8"))
            
            raise TimeoutError("Container failed to become healthy.")
        attempts += 1
        sleep(1)

    # return a testinfra connection to the container
    yield testinfra.get_host("docker://" + cast(str, container.name))

    # at the end of the test suite, destroy the container
    container.remove(v=True, force=True)


@pytest.mark.parametrize("service_name", [
    'adminapi',
    'lsn-checkpoint-push',
    'pg_egress_collect',
    'postgresql',
    'logrotate',
    'supa-shutdown',
    'services:kong',
    'services:postgrest',
    'services:gotrue',
])
def test_service_is_running(host, service_name):
    assert host.supervisor(service_name).is_running


def test_postgrest_responds_to_requests():
    res = requests.get(
        "http://localhost:8000/rest/v1/",
        headers={
            "apikey": all_in_one_envs["ANON_KEY"],
            "authorization": f"Bearer {all_in_one_envs['ANON_KEY']}",
        },
    )
    assert res.ok


def test_postgrest_can_connect_to_db():
    res = requests.get(
        "http://localhost:8000/rest/v1/buckets",
        headers={
            "apikey": all_in_one_envs["SERVICE_ROLE_KEY"],
            "authorization": f"Bearer {all_in_one_envs['SERVICE_ROLE_KEY']}",
            "accept-profile": "storage",
        },
    )
    assert res.ok
