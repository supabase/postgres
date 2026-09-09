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
    machine.succeed("UPDATE_PROFILE_CATALOG=/tmp/catalog.json update-profile site-env-17 deadbeef")
    machine.succeed("[ \"$(readlink -f /nix/var/nix/profiles/site-env-17)\" = \"${site-env-17}\" ]")

    # idempotent: same catalog again is a no-op success
    machine.succeed("UPDATE_PROFILE_CATALOG=/tmp/catalog.json update-profile site-env-17 deadbeef")

    # wrong profile for the resolved path: must refuse
    machine.fail("UPDATE_PROFILE_CATALOG=/tmp/catalog.json update-profile site-env-15 deadbeef")
  '';
}
