from conftest import run_ssh_command


def test_copy_fail_algif_aead_mitigation(host):
    """Verify algif_aead is blocked from autoloading and is not loaded."""
    result = run_ssh_command(
        host["ssh"],
        "grep -R '^install algif_aead /bin/false$' /etc/modprobe.d /usr/lib/modprobe.d",
    )
    assert result["succeeded"], (
        "algif_aead module autoload is not disabled by modprobe config.\n"
        f"stdout: {result['stdout']}\nstderr: {result['stderr']}"
    )

    result = run_ssh_command(
        host["ssh"],
        "grep -qE '^algif_aead ' /proc/modules",
    )
    assert not result["succeeded"], "algif_aead module is loaded"

    result = run_ssh_command(
        host["ssh"],
        "sudo modprobe -n -v algif_aead 2>&1",
    )
    assert result["succeeded"], f"modprobe dry-run failed: {result['stderr']}"
    assert "install /bin/false" in result["stdout"], (
        "modprobe dry-run did not resolve algif_aead to /bin/false.\n"
        f"stdout: {result['stdout']}"
    )
