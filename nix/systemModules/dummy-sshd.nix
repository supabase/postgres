{ lib, ... }:
{
  options = {
    services.openssh.settings.logLevel = lib.mkOption {
      type = lib.types.str;
    };
  };
}

# FIXME: nix run .#check-system-manager
# warning: Git tree '/data/yvan/wip/postgres' is dirty
# error:
#        … while evaluating 'strict' to select 'drvPath' on it
#          at /builtin/derivation.nix:1:552:
#        … while calling the 'derivationStrict' builtin
#          at /builtin/derivation.nix:1:208:
#        (stack trace truncated; use '--show-trace' to show the full trace)

#        error: The option `services.openssh.settings.LogLevel' does not exist. Definition values:
#        - In `/nix/store/8cpqym71jjq5frp06ypjsj1iwi3l0fln-source/nixos/modules/services/security/fail2ban.nix':
#            {
#              _type = "if";
#              condition = false;
#              content = {
#                _type = "override";
#            ...
