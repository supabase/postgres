import pytest


@pytest.fixture(scope="module", autouse=True)
def run_ansible(run_ansible_playbook):
    run_ansible_playbook("nix.yaml", verbose=True)


def test_nix_service(host):
    assert host.service("nix-daemon.service").is_running

def test_envoy_service(host):
    assert host.service("envoy.service").is_running
