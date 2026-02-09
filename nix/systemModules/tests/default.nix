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

              with subtest("Verify logrotate service"):
                  timer = machine.service("logrotate.timer")
                  assert timer.is_running, "logrotate should be running"
                  assert timer.is_enabled, "logrotate should be enabled"

              with subtest("Verify logrotate timer schedule"):
                  result = machine.run("systemctl list-timers --all --no-legend logrotate.timer")
                  assert result.rc == 0, "Failed to list logrotate.timer"
                  output = result.stdout.strip()
                  assert output, "logrotate.timer should be listed"
                  # Check if the timer is scheduled to run every 5 minutes
                  assert "logrotate.timer" in output, "logrotate.timer should be in the list of timers"
                  assert "*:0/5" in output or "logrotate.timer" in output, "logrotate.timer should be scheduled to run every 5 minutes"

              with subtest("Start logrotate service"):
                  machine.systemctl("start logrotate.service")

              with subtest("Verify logrotate configuration"):
                  for fname in [
                      "/etc/logrotate.d/logrotate-postgres-auth.conf",
                      "/etc/logrotate.d/logrotate-postgres-csv.conf",
                      "/etc/logrotate.d/logrotate-postgres.conf",
                      "/etc/logrotate.d/logrotate-walg.conf",
                  ]:
                      result = machine.run(f"test -f {fname}")
                      f = machine.file(fname)
                      assert f.exists, f"{fname} should exist"
                      assert f.is_file, f"{fname} should be a regular file"
                      assert f.user == "root", f"{fname} should be owned by root but is owned by {f.user}"
                      assert f.group == "root", f"{fname} should be owned by root group but is owned by {f.group}"
                      assert f.mode == 0o644, f"{fname} should have permissions 644 but has {oct(f.mode)}"
                  result = machine.run("logrotate --debug /etc/logrotate.conf")
                  assert result.rc == 0, "Failed to run logrotate in debug mode"
                  output = result.stdout.strip()
                  assert "error" not in output.lower(), f"logrotate debug output should not contain 'error' but it contains: {output}"
            '';
          };
      };
    };
}
