# from time import sleep


def test_gotrue_service(host):
    # sleep(5000)  # Handy for interactive debugging (with docker exec -it $CONTAINER_ID /bin/bash)
    assert host.service("gotrue.service").is_valid
    assert host.service("gotrue.service").is_running, (
        "Auth service should be running but failed: {}".format(
            host.run("systemctl status gotrue.service").stdout
        )
    )
