import pytest


@pytest.fixture(scope="module", autouse=True)
def run_ansible(run_ansible_playbook):
    run_ansible_playbook("system-manager.yaml", verbose=True)


def test_nix_service(host):
    assert host.service("nix-daemon.service").is_running


def test_system_manager_target(host):
    target = host.service("system-manager.target")
    assert target.is_running, "system-manager.target should be active"
