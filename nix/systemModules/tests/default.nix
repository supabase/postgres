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

              with subtest("Verify nginx service"):
                  assert machine.service("nginx").is_running, "nginx should be running"
            '';
          };
      };
    };
}
