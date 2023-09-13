from docker.models.containers import Container
from time import sleep
from typing import cast
import docker
import pytest
import subprocess
import testinfra

all_in_one_image_tag = "supabase/all-in-one:testinfra"
all_in_one_envs = {
    "POSTGRES_PASSWORD": "postgres",
    "JWT_SECRET": "super-secret-jwt-token-with-at-least-32-characters-long",
    "ANON_KEY": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJhbm9uIiwKICAgICJpc3MiOiAic3VwYWJhc2UtZGVtbyIsCiAgICAiaWF0IjogMTY0MTc2OTIwMCwKICAgICJleHAiOiAxNzk5NTM1NjAwCn0.dc_X5iR_VP_qT0zsiyj_I_OZ2T9FtRU2BBNWN8Bu4GE",
    "SERVICE_ROLE_KEY": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyAgCiAgICAicm9sZSI6ICJzZXJ2aWNlX3JvbGUiLAogICAgImlzcyI6ICJzdXBhYmFzZS1kZW1vIiwKICAgICJpYXQiOiAxNjQxNzY5MjAwLAogICAgImV4cCI6IDE3OTk1MzU2MDAKfQ.DaYlNEoUrrEn2Ig7tqibS-PHK5vgusbcbo7X36XVt4Q",
    "ADMIN_API_KEY": "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJyb2xlIjoic3VwYWJhc2VfYWRtaW4iLCJpc3MiOiJzdXBhYmFzZS1kZW1vIiwiaWF0IjoxNjQxNzY5MjAwLCJleHAiOjE3OTk1MzU2MDB9.Y9mSNVuTw2TdfryoaqM5wySvwQemGGWfSe9ixcklVfM",
    "DATA_VOLUME_MOUNTPOINT": "/data",
    "MACHINE_TYPE": "shared_cpu_1x_512m",
}

# TODO: spin up local Logflare for Vector tests.


# scope='session' uses the same container for all the tests;
# scope='function' uses a new container per test function.
@pytest.fixture(scope="session")
def host(request):
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
            "docker/all-in-one/Dockerfile",
            "--load",
            "--tag",
            all_in_one_image_tag,
            ".",
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

    while True:
        health = get_health(container)
        if health == "healthy":
            break
        sleep(1)

    # return a testinfra connection to the container
    yield testinfra.get_host("docker://" + cast(str, container.name))

    # at the end of the test suite, destroy the container
    container.remove(v=True, force=True)


def test_postgrest_service(host):
    postgrest = host.supervisor("services:postgrest")
    assert postgrest.is_running
