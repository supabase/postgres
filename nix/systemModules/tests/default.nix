{ self, inputs, ... }:
{
  perSystem =
    {
      lib,
      pkgs,
      ...
    }:
    {
      checks = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        check-system-manager =
          let
            toplevel = self.systemConfigs.${pkgs.system}.default;
          in
          inputs.system-manager.lib.containerTest.makeContainerTest {
            hostPkgs = pkgs;
            name = "check-system-manager";
            inherit toplevel;
            testScript = ''
              start_all()

              machine.wait_for_unit("multi-user.target")

              machine.activate()
              machine.wait_for_unit("system-manager.target")

              with subtest("Verify genesis file"):
                  assert machine.file("/etc/system-manager-genesis").exists, "/etc/system-manager-genesis should exist"
                  assert machine.file("/etc/system-manager-genesis").mode == 0o644, "/etc/system-manager-genesis should have mode 0644"
                  assert machine.file("/etc/system-manager-genesis").user == "root", "/etc/system-manager-genesis should be owned by root"
                  assert machine.file("/etc/system-manager-genesis").group == "root", "/etc/system-manager-genesis should be owned by root"
            '';
          };
      };
    };
}
