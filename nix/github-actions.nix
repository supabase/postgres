{ inputs, ... }:
let
  githubPlatforms = {
    "aarch64-linux" = "aarch64-linux";
    "aarch64-darwin" = "aarch64-darwin";
    "x86_64-linux" = "blacksmith-32vcpu-ubuntu-2404";
  };
in
{
  flake.githubActions = inputs.nix-github-actions.lib.mkGithubMatrix {
    checks = inputs.nixpkgs.lib.getAttrs [
      "x86_64-linux"
      "aarch64-linux"
      "aarch64-darwin"
    ] inputs.self.checks;
    platforms = githubPlatforms;
  };
}
