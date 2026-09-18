{ self, pkgs }:
let
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;
  update-profile = self.packages.${system}.update-profile;
  site-env-17 = self.packages.${system}."site-env-17";
in
pkgs.testers.runNixOSTest {
  name = "update-profile";
  nodes.machine =
    { ... }:
    {
      environment.systemPackages = [
        update-profile
        site-env-17
      ];
    };
  testScript = ''
    machine.succeed("echo '{\"${system}\": \"${site-env-17}\"}' > /tmp/catalog.json")
    machine.succeed("UPDATE_PROFILE_CATALOG=/tmp/catalog.json update-profile site-env-17")
    machine.succeed("[ \"$(readlink -f /nix/var/nix/profiles/site-env-17)\" = \"${site-env-17}\" ]")

    # idempotent
    machine.succeed("UPDATE_PROFILE_CATALOG=/tmp/catalog.json update-profile site-env-17")

    # path not tagged for this profile
    machine.fail("UPDATE_PROFILE_CATALOG=/tmp/catalog.json update-profile site-env-15")
  '';
}
