import pytest
import subprocess
import testinfra
from rich.console import Console

console = Console()


def pytest_addoption(parser):
    parser.addoption(
        "--flake-dir",
        action="store",
        help="Directory containing the current flake",
    )

    parser.addoption(
        "--docker-image",
        action="store",
        help="Docker image and tag to use for testing",
    )


@pytest.fixture(scope="module")
def host(request):
    flake_dir = request.config.getoption("--flake-dir")
    if not flake_dir:
        pytest.fail("--flake-dir option is required")
    docker_image = request.config.getoption("--docker-image")
    if not docker_image:
        pytest.fail("--docker-image option is required")
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
                "-v",
                f"{flake_dir}:/flake",
                "-d",
                docker_image,
            ]
        )
        .decode()
        .strip()
    )
    yield testinfra.get_host("docker://" + docker_id)
    subprocess.check_call(["docker", "rm", "-f", docker_id], stdout=subprocess.DEVNULL)


@pytest.fixture(scope="module")
def run_ansible_playbook(host):
    def _run_playbook(playbook_name, verbose=False):
        cmd = [
            "ANSIBLE_HOST_KEY_CHECKING=False",
            "ansible-playbook",
            "--connection=local",
        ]
        if verbose:
            cmd.append("-vvv")
        cmd.extend(
            [
                "-i",
                "localhost,",
                "--extra-vars",
                "@/flake/ansible/vars.yml",
                f"/flake/ansible/tests/{playbook_name}",
            ]
        )
        result = host.run(" ".join(cmd))
        if result.failed:
            console.log(result.stdout)
            console.log(result.stderr)
            pytest.fail(
                f"Ansible playbook {playbook_name} failed with return code {result.rc}"
            )

    return _run_playbook
