def pytest_addoption(parser):
    parser.addoption(
        "--ansible-dir",
        action="store",
        help="Directory containing Ansible playbooks and roles",
    )

    parser.addoption(
        "--docker-image",
        action="store",
        help="Docker image and tag to use for testing",
    )
