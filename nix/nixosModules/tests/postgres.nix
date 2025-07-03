{ self, pkgs }:
self.inputs.nixpkgs.lib.nixos.runTest {
  name = "postgres-module";
  hostPkgs = pkgs;
  nodes.server =
    { ... }:
    {
      imports = [ self.nixosModules.postgres ];
      virtualisation = {
        forwardPorts = [
          {
            from = "host";
            host.port = 13022;
            guest.port = 22;
          }
        ];
      };
      services.openssh = {
        enable = true;
      };
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIo+ulCUfJjnCVgfM4946Ih5Nm8DeZZiayYeABHGPEl7 jfroche"
      ];
      supabase.postgres = {
        enable = true;
      };
    };
  testScript =
    { ... }:
    ''
      start_all()

      server.wait_for_unit("multi-user.target")
    '';
}
