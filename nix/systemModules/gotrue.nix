{
  pkgs,
  lib,
  config,
  self,
  system,
  ...
}:
let
  cfg = config.supabase.services.gotrue;
in
{
  imports = [
    # TODO: actually open the ports it needs with ufw
    ./dummy-firewall.nix
  ];

  options = {
    supabase.services.gotrue = {
      enable = lib.mkEnableOption "Supabase (gotrue) authentication service";
    };
  };

  config = lib.mkIf cfg.enable {
    services.auth = {
      enable = true;
      package = self.inputs.gotrue.packages.${system}.default;
    };

    supabase.services.postgres = {
      initialScript = lib.mkForce (
        pkgs.writeText "init-postgres-with-password" ''
          CREATE USER supabase_admin LOGIN CREATEROLE CREATEDB REPLICATION BYPASSRLS;

          -- Supabase super admin
          CREATE USER supabase_auth_admin NOINHERIT CREATEROLE LOGIN NOREPLICATION PASSWORD 'secret';
          CREATE SCHEMA IF NOT EXISTS auth AUTHORIZATION supabase_auth_admin;
          GRANT CREATE ON DATABASE postgres TO supabase_auth_admin;
          ALTER USER supabase_auth_admin SET search_path = 'auth';

          -- FIXME: gotrue service needs a postgres role
          create role postgres superuser login; alter database postgres owner to postgres;
        ''
      );
      authentication = ''
        host supabase_auth_admin postgres samenet scram-sha-256
      '';
    };

    systemd.services.gotrue = {
      after = lib.mkForce [ "postgresql-setup.service" ];
      wantedBy = lib.mkForce [
        "system-manager.target"
      ];
    };
    services.userborn.enable = true;

    # TODO: supabase-admin-api haven't been turned into a system-manager module yet:
    #
    # systemd.services.gotrue-optimizations = {
    #   description = "gotrue (auth) optimizations";
    #   wantedBy = [ "gotrue.service" ];
    #   serviceConfig = {
    #     Type = "oneshot";
    #     # we don't want failures from this command to cause PG startup to fail
    #     ExecStart = "/bin/bash -c '/opt/supabase-admin-api optimize auth --destination-config-file-path /etc/gotrue/gotrue.generated.env ; exit 0'";
    #     ExecStartPost = "/bin/bash -c 'cp -a /etc/gotrue/gotrue.generated.env /etc/auth.d/20_generated.env ; exit 0'";
    #     User = "postgrest";
    #   };
    # };

    # TODO: that's what the activation script was doing:
    # cp $out/etc/auth.env /etc/auth.d/20_generated.env
    # chown gotrue:gotrue /etc/auth.d/20_generated.env
    # chmod 600 /etc/auth.d/20_generated.env
  };
}
