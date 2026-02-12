{ lib, ... }:
let
  postgresqlDefaults = lib.types.submodule {
    options = {
      port = lib.mkOption {
        type = lib.types.str;
        default = "5435";
      };
      host = lib.mkOption {
        type = lib.types.str;
        default = "localhost";
      };
      superuser = lib.mkOption {
        type = lib.types.str;
        default = "supabase_admin";
      };
    };
  };
  postgresqlVersion = lib.types.submodule {
    options = {
      version = lib.mkOption { type = lib.types.str; };
      hash = lib.mkOption { type = lib.types.str; };
      revision = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
    };
  };
  supabaseSubmodule = lib.types.submodule {
    options = {
      defaults = lib.mkOption { type = postgresqlDefaults; };
      supportedPostgresVersions = lib.mkOption {
        type = lib.types.attrsOf (lib.types.attrsOf postgresqlVersion);
        default = { };
      };
    };
  };
in
{
  flake = {
    options = {
      supabase = lib.mkOption { type = supabaseSubmodule; };
    };
    config.supabase = {
      defaults = { };
      supportedPostgresVersions = {
        postgres = {
          "15" = {
            version = "15.16";
            hash = "sha256-aV7imne+H1AQ4Q82Z2lvKYcVh/eqMR6twfgJvqKHz0g=";
          };
          "17" = {
            version = "17.8";
            hash = "sha256-qI0ZXdk3MEUtDPoaEYlnINbRughLwr59f8VX+k5BWKA=";
          };
        };
        orioledb = {
          "17" = {
            version = "17_16";
            hash = "sha256-Xm9IUsvmlcayNQH8TCvHoIV23xkt/WQV0Oy4CiJkywc=";
          };
        };
      };
    };
  };
}
