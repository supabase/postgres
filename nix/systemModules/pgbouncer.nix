{
  lib,
  pkgs,
  nixosModulesPath,
  system,
  config,
  ...
}:
let
  cfg = config.supabase.services.pgbouncer;

  # From https://github.com/mightyiam/catppuccin-nix/blob/main/modules/lib/default.nix#L78-L89
  fromINI =
    file:
    let
      json = pkgs.runCommand "converted.json" { } ''
        ${lib.getExe pkgs.jc} --ini < ${file} > $out
      '';
    in
    builtins.fromJSON (builtins.readFile json);
in
{
  imports = [
    # TODO: actually open the ports it needs with ufw
    ./dummy-firewall.nix
  ]
  ++ map (path: nixosModulesPath + path) [
    "/services/databases/pgbouncer.nix"
  ];

  options = {
    supabase.services.pgbouncer = {
      enable = lib.mkEnableOption "Whether to enable PostgreSQL connection pooler.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.etc = {
      # By default allow ssl connections.
      "/etc/pgbouncer-custom/ssl-config.ini".text = ''
        client_tls_sslmode = allow
      '';
    };

    # Nixpkgs pgbouncer systemd service is quite what we had set up by ansible before:
    #
    # [Service]
    # Type=notify
    # User=pgbouncer
    # ExecStart=/usr/local/bin/pgbouncer /etc/pgbouncer/pgbouncer.ini
    # ExecReload=/bin/kill -HUP $MAINPID
    # KillSignal=SIGINT
    # LimitNOFILE=65536
    # Restart=always
    # RestartSec=5
    services.pgbouncer = {
      enable = true;
      package =
        (import (fetchTarball {
          # pgbouncer v1.19.0
          url = "https://github.com/NixOS/nixpkgs/archive/db7534df5fb9b7dfd3404ec26d977997ff2cc1a0.tar.gz";
          sha256 = "sha256:0lrsnz80a3jfjdyjs4njipvmq34w6wjr5ql645z1l1s9f9cyvk0g";
        }) { system = system; }).pgbouncer;
      settings =
        let
          iniJson = fromINI ./pgbouncer/pgbouncer.ini;
        in
        iniJson
        // {
          pgbouncer = iniJson.pgbouncer // {
            # jc --ini treat all values as strings, so we must manually convert
            # every numeric option to its expected type for NixOS module validation ...
            default_pool_size = lib.toInt iniJson.pgbouncer.default_pool_size;
            listen_port = lib.toInt iniJson.pgbouncer.listen_port;
          };
        };
      user = "pgbouncer"; # n.b. this is the nixpkgs default, but since everything depends on it ...
      group = "pgbouncer"; # ... we might as well be explicit here!
    };
    systemd.services.pgbouncer = {
      wantedBy = lib.mkForce [
        "system-manager.target"
      ];
    };

    # TODO: double check if all these are really needed
    systemd.tmpfiles.rules = [
      "d /run/pgbouncer                                    2775 pgbouncer postgres  - -"
      "d /etc/pgbouncer-custom                             0775 pgbouncer pgbouncer - -"
      "C /etc/pgbouncer/userlist.txt                       0700 pgbouncer pgbouncer - -"
      "C /etc/pgbouncer-custom/custom-overrides.ini        0664 pgbouncer pgbouncer - -"
      "C /etc/pgbouncer-custom/generated-optimizations.ini 0664 pgbouncer pgbouncer - -"
      "C /etc/pgbouncer-custom/ssl-config.ini              0664 pgbouncer pgbouncer - -"
    ];
  };
}
