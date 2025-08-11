{ inputs, ... }:
let
  githubPlatforms = {
    "x86_64-linux" = "large-linux-x86";
    "aarch64-linux" = "large-linux-arm";
    "aarch64-darwin" = "macos-latest-xlarge";
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
