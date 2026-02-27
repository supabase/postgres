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

              with subtest("Verify ssh config"):
                  assert machine.file("/etc/ssh/sshd_config.d/local.conf").exists, "/etc/ssh/sshd_config.d/local.conf should exist"
                  assert machine.file("/etc/ssh/sshd_config.d/local.conf").mode == 0o644, "/etc/ssh/sshd_config.d/local.conf should have mode 0644"
                  assert machine.file("/etc/ssh/sshd_config.d/local.conf").user == "root", "/etc/ssh/sshd_config.d/local.conf should be owned by root"
                  assert machine.file("/etc/ssh/sshd_config.d/local.conf").group == "root", "/etc/ssh/sshd_config.d/local.conf should be owned by root"
                  assert machine.file("/etc/ssh/sshd_config.d/local.conf").contains("Match Address"), "/etc/ssh/sshd_config.d/local.conf should contain 'Match Address'"
            '';
          };
      };
    };
}
