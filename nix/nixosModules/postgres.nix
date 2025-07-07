{ self, withSystem }:
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.supabase.postgres;
  pgsodium_getkey = pkgs.lib.getExe (
    withSystem pkgs.system ({ self', ... }: self'.packages.pgsodium_getkey_urandom)
  );
  defaultSettings = self.supabase.defaults.settings // {
    "pgsodium.getkey_script" = pgsodium_getkey;
    "vault.getkey_script" = pgsodium_getkey;
  };
  postgresqlWithExtension =
    postgresql: extensions:
    let
      majorVersion = lib.versions.major postgresql.version;
      pkg = pkgs.buildEnv {
        name = "postgresql-${majorVersion}";
        paths = [
          postgresql
          postgresql.lib
        ] ++ extensions;
        passthru = {
          inherit (postgresql) version psqlSchema;
          lib = pkg;
          withPackages = _: pkg;
        };
        nativeBuildInputs = [ pkgs.makeWrapper ];
        pathsToLink = [
          "/"
          "/bin"
          "/lib"
        ];
        postBuild = ''
          wrapProgram $out/bin/postgres --set NIX_PGLIBDIR $out/lib
          wrapProgram $out/bin/pg_ctl --set NIX_PGLIBDIR $out/lib
          wrapProgram $out/bin/pg_upgrade --set NIX_PGLIBDIR $out/lib
        '';
      };
    in
    pkg;
in
{
  options.supabase.postgres = {
    enable = lib.mkEnableOption "PostgreSQL";
    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "PostgreSQL extensions to be installed. Defaults to all extensions";
    };
    settings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "PostgreSQL configuration settings";
    };
  };

  config = lib.mkIf cfg.enable {
    services.postgresql =
      let
        extensions =
          self':
          if cfg.extensions == [ ] then
            builtins.attrValues self'.legacyPackages.psql_15.exts
          else
            lib.getAttrs (map (ext: ext.pname) cfg.extensions) self'.legacyPackages.psql_15.exts;
      in
      {
        enable = true;
        enableTCPIP = true;
        package = withSystem pkgs.system (
          { self', ... }: postgresqlWithExtension self'.packages.postgresql_15 (extensions self')
        );
        settings = defaultSettings // cfg.settings;
        checkConfig = false;
      };
    systemd.tmpfiles.rules = [ "d '/etc/postgresql-custom' 0750 postgres postgres - -" ];
    environment.etc."postgresql-custom/read-replica.conf".source = ../../ansible/files/postgresql_config/custom_read_replica.conf.j2;
  };
}
