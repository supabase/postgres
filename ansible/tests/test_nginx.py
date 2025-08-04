import pytest
import subprocess
import testinfra
from rich.console import Console

console = Console()


@pytest.fixture(scope="session")
def host(request):
    ansible_dir = request.config.getoption("--ansible-dir")
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
                f"{ansible_dir}/:/ansible/",
                "-d",
                "ubuntu-cloudimg-with-tools:0.1",
            ]
        )
        .decode()
        .strip()
    )
    yield testinfra.get_host("docker://" + docker_id)
    subprocess.check_call(["docker", "rm", "-f", docker_id], stdout=subprocess.DEVNULL)


@pytest.fixture(scope="session", autouse=True)
def run_ansible(host):
    cmd = [
        "ANSIBLE_HOST_KEY_CHECKING=False",
        "ansible-playbook",
        "--connection=local",
        "-i",
        "localhost,",
        "--extra-vars",
        "@/ansible/vars.yml",
        "/ansible/tests/nginx.yaml",
    ]
    result = host.run(" ".join(cmd))
    if result.failed:
        console.log(result.stdout)
        console.log(result.stderr)
        raise pytest.fail(
            "Ansible playbook nginx.yaml failed with return code {}".format(result.rc)
        )


def test_nginx_service(host):
    assert host.service("nginx.service").is_valid
    assert host.service("nginx.service").is_running
