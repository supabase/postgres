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
            version = "15.20";
            hash = "sha256-MOZcu7dxo5tVPtLffmViLmVkeu1V28Gb0P6FP/CghEI=";
          };
          "17" = {
            version = "17.12";
            hash = "sha256-nPE2pwPY7i+DRlxDvk6ejnkwyCsL+6E75+JTe+dprFU=";
          };
        };
        orioledb = {
          "17" = {
            version = "17_23";
            hash = "sha256-0qCbMD0aKreinaOH6epwPDIMSfJU2rs2oCnXVng3WUM=";
          };
        };
      };
    };
  };
}
