import pytest


@pytest.fixture(scope="module", autouse=True)
def run_ansible(run_ansible_playbook):
    run_ansible_playbook("nginx.yaml")


def test_nginx_service(host):
    assert host.service("nginx.service").is_valid
    assert host.service("nginx.service").is_running
