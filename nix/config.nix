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
            version = "15.14";
            hash = "sha256-Bt110wXNOHDuYrOTLmYcYkVD6vmuK6N83sCk+O3QUdI=";
          };
          "17" = {
            version = "17.6";
            hash = "sha256-4GMKNgCuonURcVVjJZ7CERzV9DU6SwQOC+gn+UzXqLA=";
          };
        };
        orioledb = {
          "17" = {
            version = "17_20";
            revision = "b8970548a74d2adec467ce7c99469a34edbc563b";
            hash = "sha256-yQCUw8A11heKWASlZS57L4etFNbsssZ2Z9XPpYT9do4=";
          };
        };
      };
    };
  };
}
