{ self, pkgs }:
pkgs.writeShellApplication {
  name = "ansible-test";
  runtimeInputs = with pkgs; [
    (python3.withPackages (
      ps: with ps; [
        requests
        pytest
        pytest-testinfra
        pytest-xdist
        rich
      ]
    ))
  ];
  text = ''
    echo "Running Ansible tests..."
    FLAKE_DIR=${self}
    pytest -p no:cacheprovider -v -n auto $FLAKE_DIR/ansible/tests --flake-dir=$FLAKE_DIR --docker-image=supabase/ansible-test:latest "$@"
  '';
  meta = {
    description = "Ansible test runner";
  };
}
