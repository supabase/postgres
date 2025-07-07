{ self, pkgs }:
let
  toplevel = (
    self.inputs.system-manager.lib.makeSystemConfig { modules = [ self.systemModules.postgres ]; }
  );
in
pkgs.testers.nonNixOSDistros.ubuntu."20_04" {
  testScript = ''
    # Start the VM
    start_all()

    # Wait for the system to be ready
    vm.wait_for_unit("default.target")

    # Activate the systemManager configuration
    vm.succeed("${toplevel}/bin/activate 2>&1 | tee /tmp/output.log")
    output = vm.succeed("cat /tmp/output.log")
    print("Output from activation:\n", output)
    vm.succeed("! grep -F 'ERROR' /tmp/output.log")

    # Wait for systemManager target
    vm.wait_for_unit("system-manager.target")

    # Test that our configuration file exists
    vm.succeed("test -f /etc/postgresql-custom/read-replica.conf")

    print("All tests passed!")
  '';

  extraPathsToRegister = [ toplevel ];
  sharedDirs = { };
}
