{ inputs, ... }:
let
  ghWorkflows = builtins.attrNames (builtins.readDir ../.github/workflows);
  lintedWorkflows = [
    "ami-release-nix.yml"
    "nix-build.yml"
    "nix-eval.yml"
    "testinfra-ami-build.yml"
  ];
in
{
  imports = [ inputs.git-hooks.flakeModule ];
  perSystem =
    { config, pkgs, ... }:
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

            shellcheck = {
              enable = true;
              excludes = [
                # TODO fix these :pray:
                "ansible/files/admin_api_scripts/grow_fs.sh"
                "ansible/files/admin_api_scripts/pg_upgrade_scripts/initiate.sh"
                "nix/init.sh"
                "nix/packages/cli-config/supabase-postgres-init.sh"
                "nix/tests/util/pgsodium_getkey.sh"
                "nix/tests/util/pgsodium_getkey_arb.sh"
                "tests/pg_upgrade/debug.sh"
                "tests/pg_upgrade/scripts/entrypoint.sh"
              ];
            };

            treefmt = {
              enable = true;
              package = config.treefmt.build.wrapper;
              pass_filenames = false;
              verbose = true;
            };

            no-cli-in-postgres-release = {
              enable = true;
              name = "no-cli-in-postgres-release";
              description = "Prevent -cli suffix in postgres_release values in ansible/vars.yml";
              entry = builtins.toString (
                pkgs.writeShellScript "no-cli-in-postgres-release" ''
                  if [ -f ansible/vars.yml ]; then
                    if ${pkgs.gnugrep}/bin/grep -E '^\s+postgres(orioledb-)?[0-9]+:.*-cli' ansible/vars.yml; then
                      echo ""
                      echo "ERROR: postgres_release values in ansible/vars.yml must not contain '-cli' suffix."
                      echo "The -cli tag is generated automatically by the AMI release workflow."
                      exit 1
                    fi
                  fi
                ''
              );
              files = "^ansible/vars\\.yml$";
              language = "system";
              verbose = true;
            };
          };
        };
      };
    };
}
