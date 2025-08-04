def test_nginx_service(host):
    assert host.service("nginx.service").is_valid
    assert host.service("nginx.service").is_running
