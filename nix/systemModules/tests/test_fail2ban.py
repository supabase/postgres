# from time import sleep


def test_fail2ban_service(host):
    # sleep(5000) # Handy for interactive debugging (with docker exec -it $CONTAINER_ID /bin/bash)
    assert host.service("fail2ban.service").is_valid
    assert host.service("fail2ban.service").is_running, (
        "Fail2Ban service should be running but failed: {}".format(
            host.run("systemctl status fail2ban.service").stdout
        )
    )
