{
  lib,
  nixosModulesPath,
  config,
  ...
}:
let
  cfg = config.supabase.services.fail2ban;
in
{
  imports = [
    # We use a dummmy sshd module to workaround this error when importing "/services/networking/ssh/sshd.nix":
    #   error: The option `users' in module `/nix/store/...-source/nix/modules'
    #   would be a parent of the following options, but its type `attribute set' does not support nested options.
    #   - option(s) with prefix `users.users' in module `/nix/store/...-source/nixos/modules/services/networking/ssh/sshd.nix'
    # FIXME: it would be better to rely on userborn in system-manager:
    # https://github.com/numtide/system-manager/pull/266
    ./dummy-sshd.nix
  ]
  ++ map (path: nixosModulesPath + path) [
    # "/config/console.nix"
    # "/config/shells-environment.nix"
    # "/config/system-path.nix"
    # "/programs/i3lock.nix"
    # "/programs/ssh.nix"
    # "/security/pam.nix"
    # "/services/networking/firewall.nix"
    # "/services/networking/ssh/sshd.nix"
    "/services/security/fail2ban.nix"
    # "/system/boot/kernel.nix" # ERROR: The option `boot' in module `/nix/store/...-source/nix/modules/upstream/nixpkgs'
    # would be a parent of the following options, but its type `raw value' does not support nested options.
  ];

  options = {
    supabase.services.fail2ban = {
      enable = lib.mkEnableOption "Fail2Ban";
    };
  };

  config = lib.mkIf cfg.enable {
    # TODO: (last bit form Ansible task)
    # - name: Configure journald
    #   copy:
    #     src: files/fail2ban_config/jail-ssh.conf
    #     dest: /etc/fail2ban/jail.d/sshd.local
    #   when: debpkg_mode or nixpkg_mode
    supabase.services.fail2ban = {
      # enable = true; # TODO: don't use nixpkgs fail2ban
      bantime = "3600";
      jails = {
        postgresql = {
          settings = {
            enabled = true;
            port = "5432";
            protocol = "tcp";
            filter = "postgresql";
            logpath = "/var/log/postgresql/auth-failures.csv";
            maxretry = 3;
            ignoreip = "192.168.0.0/16 172.17.1.0/20";
          };
        };
        pgbouncer = {
          settings = {
            enabled = true;
            port = "6543";
            protocol = "tcp";
            filter = "pgbouncer";
            backend = "systemd[journalflags=1]";
            maxretry = 3;
          };
        };
      };
      # TODO: extraPackages = [ pkgs.nftables ];
    };

    environment.etc = {
      "fail2ban/jail.local".text = ''
        [DEFAULT]
        banaction = nftables-multiport
        banaction_allports = nftables-allports
      '';

      "fail2ban/filter.d/postgresql.conf".text = ''
        [Definition]
        failregex = ^.*,.*,.*,.*,"<HOST>:.*password authentication failed for user.*$
        ignoreregex = ^.*,.*,.*,.*,"127\.0\.0\.1.*password authentication failed for user.*$
                      ^.*,.*,.*,.*,"<HOST>:.*password authentication failed for user ""supabase_admin".*$
                      ^.*,.*,.*,.*,"<HOST>:.*password authentication failed for user ""supabase_auth_admin".*$
                      ^.*,.*,.*,.*,"<HOST>:.*password authentication failed for user ""supabase_storage_admin".*$
                      ^.*,.*,.*,.*,"<HOST>:.*password authentication failed for user ""authenticator".*$
                      ^.*,.*,.*,.*,"<HOST>:.*password authentication failed for user ""pgbouncer".*$
      '';

      "fail2ban/filter.d/pgbouncer.conf".text = ''
        [Definition]
        failregex = ^.+@<HOST>:.+password authentication failed$
        journalmatch = _SYSTEMD_UNIT=pgbouncer.service
      '';
    };

    systemd.services.fail2ban = {
      wantedBy = lib.mkForce [
        "system-manager.target"
      ];
      # TODO:
      # after = [ "nftables.service" ];
      # wants = [ "nftables.service" ];
    };
  };
}
