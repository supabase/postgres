# from time import sleep


def test_pgbouncer_service(host):
    # sleep(5000)  # Handy for interactive debugging (with docker exec -it $CONTAINER_ID /bin/bash)
    assert host.service("pgbouncer.service").is_valid
    assert host.service("pgbouncer.service").is_running, (
        "Auth service should be running but failed: {}".format(
            host.run("systemctl status pgbouncer.service").stdout
        )
    )


# FIXME: AssertionError: Auth service should be running but failed: × pgbouncer.service - PgBouncer - PostgreSQL connection pooler
#        Loaded: loaded (/etc/systemd/system/pgbouncer.service; enabled; preset: enabled)
#        Active: failed (Result: exit-code) since Fri 2025-09-19 12:36:00 UTC; 12s ago
#       Process: 372 ExecStart=/nix/store/bcj53gxm9i2y4hd21jr7zpi2r1hw8wlq-pgbouncer-1.24.1/bin/pgbouncer /etc/pgbouncer/pgbouncer.ini (code=exited, status=217/USER)
#      Main PID: 372 (code=exited, status=217/USER)
#           CPU: 4ms
#
#   Sep 19 12:36:00 f803c2922bff systemd[1]: Starting pgbouncer.service - PgBouncer - PostgreSQL connection pooler...
#   Sep 19 12:36:00 f803c2922bff (gbouncer)[372]: pgbouncer.service: Failed to determine user credentials: No such process
#   Sep 19 12:36:00 f803c2922bff systemd[1]: pgbouncer.service: Main process exited, code=exited, status=217/USER
#   Sep 19 12:36:00 f803c2922bff systemd[1]: pgbouncer.service: Failed with result 'exit-code'.
#   Sep 19 12:36:00 f803c2922bff systemd[1]: Failed to start pgbouncer.service - PgBouncer - PostgreSQL connection pooler.
