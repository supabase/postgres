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
      settings = lib.mkOption {
        type = lib.types.attrs;
        default = {
          authentication_timeout = "1min";
          "auto_explain.log_min_duration" = "10s";
          checkpoint_completion_target = "0.5";
          checkpoint_flush_after = "256kB";
          cluster_name = "main";
          "cron.database_name" = "postgres";
          db_user_namespace = "off";
          default_text_search_config = "pg_catalog.english";
          effective_cache_size = "128MB";
          extra_float_digits = "0";
          include = "/etc/postgresql-custom/read-replica.conf";
          jit = "off";
          jit_provider = "llvmjit";
          lc_messages = "en_US.UTF-8";
          lc_monetary = "en_US.UTF-8";
          lc_numeric = "en_US.UTF-8";
          lc_time = "en_US.UTF-8";
          listen_addresses = "*";
          log_destination = "stderr";
          log_line_prefix = "%h %m [%p] %q%u@%d ";
          log_statement = "ddl";
          log_timezone = "UTC";
          max_replication_slots = "5";
          max_slot_wal_keep_size = "4096";
          max_wal_senders = "10";
          password_encryption = "scram-sha-256";
          port = 5432;
          row_security = "on";
          shared_buffers = "128MB";
          shared_preload_libraries = "pg_stat_statements, pgaudit, plpgsql, plpgsql_check, pg_cron, pg_net, pgsodium, timescaledb, auto_explain, pg_tle, plan_filter, supabase_vault";
          ssl = "off";
          ssl_ca_file = "";
          ssl_cert_file = "";
          ssl_ciphers = "HIGH:MEDIUM:+3DES:!aNULL";
          ssl_crl_dir = "";
          ssl_crl_file = "";
          ssl_dh_params_file = "";
          ssl_ecdh_curve = "prime256v1";
          ssl_key_file = "";
          ssl_max_protocol_version = "";
          ssl_min_protocol_version = "TLSv1.2";
          ssl_passphrase_command = "";
          ssl_passphrase_command_supports_reload = "off";
          ssl_prefer_server_ciphers = "on";
          timezone = "UTC";
          wal_level = "logical";
        };
        description = "PostgreSQL configuration settings";
      };
    };
  };
  postgresqlVersion = lib.types.submodule {
    options = {
      version = lib.mkOption { type = lib.types.str; };
      hash = lib.mkOption { type = lib.types.str; };
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
            version = "15.8";
            hash = "sha256-RANRX5pp7rPv68mPMLjGlhIr/fiV6Ss7I/W452nty2o=";
          };
          "17" = {
            version = "17.4";
            hash = "sha256-xGBbc/6hGWNAZpn5Sblm5dFzp+4Myu+JON7AyoqZX+c=";
          };
        };
        orioledb = {
          "17" = {
            version = "17_6";
            hash = "sha256-HbuTcXNanFOl9YfvlSzQJon8CfAhc8TFwo/y7jXy51w=";
          };
        };
      };
    };
  };
}
