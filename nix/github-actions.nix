{ inputs, ... }:
{
  flake.githubActions = inputs.nix-github-actions.lib.mkGithubMatrix {
    checks = inputs.nixpkgs.lib.getAttrs [ "x86_64-linux" ] inputs.self.checks;
  };
}
