def test_envoy_service(host):
    assert host.service("envoy.service").is_valid
    assert host.service("envoy.service").is_running
