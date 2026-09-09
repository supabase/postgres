{ self, pkgs }:
let
  system = pkgs.pkgsLinux.stdenv.hostPlatform.system;
  site-update = self.packages.${system}.site-update;
  site-env-17 = self.packages.${system}."site-env-17";
in
pkgs.testers.runNixOSTest {
  name = "site-update";
  nodes.machine =
    { ... }:
    {
      environment.systemPackages = [
        site-update
        site-env-17
      ];
    };
  testScript = ''
    machine.succeed("echo '{\"${system}\": \"${site-env-17}\"}' > /tmp/catalog.json")
    machine.succeed("SITE_UPDATE_CATALOG=/tmp/catalog.json site-update deadbeef site-env-17")
    machine.succeed("[ \"$(readlink -f /nix/var/nix/profiles/site-env-17)\" = \"${site-env-17}\" ]")

    # idempotent: same catalog again is a no-op success
    machine.succeed("SITE_UPDATE_CATALOG=/tmp/catalog.json site-update deadbeef site-env-17")

    # wrong env for the resolved path: must refuse
    machine.fail("SITE_UPDATE_CATALOG=/tmp/catalog.json site-update deadbeef site-env-15")
  '';
}
