import pytest
import shutil
import subprocess
import testinfra
import time
from rich.console import Console

console = Console()


def pytest_addoption(parser):
    parser.addoption(
        "--image-name",
        action="store",
        help="Docker image and tag to use for testing",
    )
    parser.addoption(
        "--image-path",
        action="store",
        help="Compressed Docker image to load for testing",
    )

    parser.addoption(
        "--force-docker",
        action="store_true",
        help="Force using Docker instead of Podman for testing",
    )


@pytest.fixture(scope="session")
def host(request):
    force_docker = request.config.getoption("--force-docker")
    image_name = request.config.getoption("--image-name")
    image_path = request.config.getoption("--image-path")
    if not force_docker and shutil.which("podman"):
        console.log("Using Podman for testing")
        with console.status("Loading image..."):
            subprocess.check_output(["podman", "load", "-q", "-i", image_path])
        podman_id = (
            subprocess.check_output(
                [
                    "podman",
                    "run",
                    "--cap-add",
                    "SYS_ADMIN",
                    "-d",
                    image_name,
                ]
            )
            .decode()
            .strip()
        )
        yield testinfra.get_host("podman://" + podman_id)
        with console.status("Cleaning up..."):
            subprocess.check_call(
                ["podman", "rm", "-f", podman_id], stdout=subprocess.DEVNULL
            )
    else:
        console.log("Using Docker for testing")
        with console.status("Loading image..."):
            subprocess.check_output(["docker", "load", "-q", "-i", image_path])
        docker_id = (
            subprocess.check_output(
                [
                    "docker",
                    "run",
                    "--privileged",
                    "--cap-add",
                    "SYS_ADMIN",
                    "--security-opt",
                    "seccomp=unconfined",
                    "--cgroup-parent=docker.slice",
                    "--cgroupns",
                    "private",
                    "-d",
                    image_name,
                ]
            )
            .decode()
            .strip()
        )
        yield testinfra.get_host("docker://" + docker_id)
        with console.status("Cleaning up..."):
            subprocess.check_call(
                ["docker", "rm", "-f", docker_id], stdout=subprocess.DEVNULL
            )


def wait_for_target(host, target, timeout=60):
    start_time = time.time()
    while time.time() - start_time < timeout:
        result = host.run(f"systemctl is-active {target}")
        if result.rc == 0:
            return True
        time.sleep(1)
    return False


@pytest.fixture(scope="session", autouse=True)
def activate_system_manager(host):
    with console.status("Waiting systemd to be ready..."):
        assert wait_for_target(host, "multi-user.target")
    result = host.run("activate")
    console.log(result.stdout)
    console.log(result.stderr)
    if result.failed:
        raise pytest.fail(
            "System manager activation failed with return code {}".format(result.rc)
        )
