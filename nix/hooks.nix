{ inputs, ... }:
let
  ghWorkflows = builtins.attrNames (builtins.readDir ../.github/workflows);
  lintedWorkflows = [
    "nix-eval.yml"
    "nix-build.yml"
    "testinfra-ami-build.yml"
    "ami-release-nix.yml"
    "ami-release-nix-single.yml"
  ];
in
{
  imports = [ inputs.git-hooks.flakeModule ];
  perSystem =
    { config, ... }:
    {
      pre-commit = {
        check.enable = true;
        settings = {
          hooks = {
            actionlint = {
              enable = true;
              excludes = builtins.filter (name: !builtins.elem name lintedWorkflows) ghWorkflows;
              verbose = true;
            };

            treefmt = {
              enable = true;
              package = config.treefmt.build.wrapper;
              pass_filenames = false;
              verbose = true;
            };
          };
        };
      };
    };
}
