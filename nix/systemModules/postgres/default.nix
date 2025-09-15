{
  lib,
  config,
  pkgs,
  self,
  ...
}:
let
  cfg = config.supabase.services.postgres;
  defaultUser = "postgres";
  defaultGroup = "postgres";

  isOrioleDB = (builtins.match "[0-9][0-9]_.*" cfg.package.version) != null;
  is17 = (builtins.substring 0 2 cfg.package.version) == "17";

  toStr =
    value:
    if true == value then
      "yes"
    else if false == value then
      "no"
    else if builtins.isString value then
      "'${lib.replaceStrings [ "'" ] [ "''" ] value}'"
    else
      builtins.toString value;

  # The main PostgreSQL configuration file.
  configFile = pkgs.writeText "postgresql.conf" (
    lib.concatStringsSep "\n" (
      lib.mapAttrsToList (n: v: "${n} = ${toStr v}") (
        lib.filterAttrs (lib.const (x: x != null)) cfg.settings
      )
    )
  );
  pg_hba = pkgs.writeText "pg_hba.conf" (
    cfg.authentication + self.supabase.postgres.defaults.authentication
  );
  pg_ident = pkgs.writeText "pg_ident.conf" ''
    # MAPNAME       SYSTEM-USERNAME         PG-USERNAME
    supabase_map  postgres   postgres
    supabase_map  root       postgres
    supabase_map  ubuntu     postgres

    # supabase-specific users
    supabase_map  gotrue     supabase_auth_admin
    supabase_map  postgrest  authenticator
    supabase_map  adminapi   postgres
  '';

  read-replica-conf = pkgs.writeText "read-replica.conf" ''
    # hot_standby = on
    # restore_command = '/usr/bin/admin-mgr wal-fetch %f %p >> /var/log/wal-g/wal-fetch.log 2>&1'
    # recovery_target_timeline = 'latest'

    # primary_conninfo = 'host=localhost port=6543 user=replication'
  '';

in
{
  options = {
    supabase.services.postgres = {
      enable = lib.mkEnableOption "Postgres";
      package = lib.mkOption {
        type = lib.types.package;
        description = ''
          The package being used by postgresql.
        '';
      };
      settings = lib.mkOption {
        type =
          with lib.types;
          submodule {
            freeformType = attrsOf (oneOf [
              bool
              float
              int
              str
            ]);
            options = {
              shared_preload_libraries = lib.mkOption {
                type = nullOr (coercedTo (listOf str) (lib.concatStringsSep ",") commas);
                default = null;
                example = literalExpression ''[ "auto_explain" "anon" ]'';
                description = ''
                  List of libraries to be preloaded.
                '';
              };
            };
          };
        default = { };
        description = ''
          PostgreSQL configuration. Refer to
          <https://www.postgresql.org/docs/current/config-setting.html#CONFIG-SETTING-CONFIGURATION-FILE>
          for an overview of `postgresql.conf`.

          ::: {.note}
          String values will automatically be enclosed in single quotes. Single quotes will be
          escaped with two single quotes as described by the upstream documentation linked above.
          :::
        '';
      };

      authentication = lib.mkOption {
        type = lib.types.lines;
        default = "";
        description = ''
          Defines how users authenticate themselves to the server. See the
          [PostgreSQL documentation for pg_hba.conf](https://www.postgresql.org/docs/current/auth-pg-hba-conf.html)
          for details on the expected format of this option. By default,
          peer based authentication will be used for users connecting
          via the Unix socket, and md5 password authentication will be
          used for users connecting via TCP. Any added rules will be
          inserted above the default rules. If you'd like to replace the
          default rules entirely, you can use `lib.mkForce` in your
          module.
        '';
      };

      environmentVariables = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {
          LANG = "en_US.UTF-8";
          LANGUAGE = "en_US.UTF-8";
          LC_ALL = "en_US.UTF-8";
          LC_CTYPE = "en_US.UTF-8";
          LOCALE_ARCHIVE = "/usr/lib/locale/locale-archive";
        };
        description = ''
          A set of environment variables to be exported in the global
          environment for all users. These will be set in `/etc/profile.d/postgresql.sh`.
        '';
      };

      dataDir = lib.mkOption {
        type = lib.types.path;
        default = "/data/pgdata";
        description = ''
          The data directory for PostgreSQL. If left as the default value
          this directory will automatically be created before the PostgreSQL server starts, otherwise
          the sysadmin is responsible for ensuring the directory exists with appropriate ownership
          and permissions.
        '';
      };

      superUser = lib.mkOption {
        type = lib.types.str;
        default = "postgres";
        internal = true;
        readOnly = true;
        description = ''
          PostgreSQL superuser account to use for various operations. Internal since changing
          this value would lead to breakage while setting up databases.
        '';
      };

      initdbArgs = lib.mkOption {
        type = with lib.types; listOf str;
        default = [
          "--allow-group-access"
          "--username=${cfg.superUser}"
        ]
        ++ (lib.optionals (isOrioleDB || is17) [
          "--locale-provider=icu"
          "--encoding=UTF-8"
          "--icu-locale=en_US.UTF-8"
        ]);
        description = ''
          Additional arguments passed to `initdb` during data dir
          initialisation.
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable {

    services.userborn.enable = true;

    users.groups.postgres = { };
    users.users.postgres = {
      isSystemUser = true;
      uid = config.ids.uids.postgres;
      group = "postgres";
      home = "${cfg.dataDir}";
      useDefaultShell = true;
    };

    systemd.tmpfiles.rules = [
      "d /home/postgres 0755 ${defaultUser} ${defaultGroup} -"
      "d /var/log/postgresql 0755 ${defaultUser} ${defaultGroup} -"
      "d /var/lib/postgresql 0755 ${defaultUser} ${defaultGroup} -"
      "d /etc/postgresql 0775 ${defaultUser} ${defaultGroup} -"
      "d /etc/postgresql-custom 0775 ${defaultUser} ${defaultGroup} -"
      "d ${cfg.dataDir} 0750 ${defaultUser} ${defaultGroup} -"
      "d /usr/lib/postgresql 0755 root root -"

      # Create symlinks
      "L+ /var/lib/postgresql/data - - - - ${cfg.dataDir}"
      "L+ /usr/lib/postgresql/bin - - - - ${cfg.package}/bin"
      "L+ /usr/lib/postgresql/share - - - - ${cfg.package}/share"
      "L+ /usr/lib/postgresql/lib - - - - ${cfg.package}/lib"

      # Copy configuration files
      "C /etc/postgresql/pg_hba.conf 0440 ${defaultUser} ${defaultGroup} - ${pg_hba}"
      "C /etc/postgresql/pg_ident.conf 0440 ${defaultUser} ${defaultGroup} - ${pg_ident}"
      "C /etc/postgresql/postgresql.conf 0440 ${defaultUser} ${defaultGroup} - ${configFile}"
      "C /etc/postgresql-custom/read-replica.conf 0440 ${defaultUser} ${defaultGroup} - ${read-replica-conf}"
    ];

    environment = {
      systemPackages = [ cfg.package ];

      etc = {
        "locale.gen".text = ''
          C.UTF-8 UTF-8
          en_US.UTF-8 UTF-8
        '';
        "profile.d/postgresql.sh".text = builtins.concatStringsSep "\n" (
          lib.mapAttrsToList (key: value: ''export ${key}="${value}"'') (cfg.environmentVariables)
        );
      };
    };

    supabase.services.postgres.settings = lib.mkMerge [
      {
        hba_file = "/etc/postgresql/pg_hba.conf";
        log_destination = "stderr";
        "pgsodium.getkey_script" = lib.getExe self.packages.${pkgs.system}.pgsodium_getkey_readonly;
        "vault.getkey_script" = lib.getExe self.packages.${pkgs.system}.pgsodium_getkey_readonly;
        shared_preload_libraries = [
          "auto_explain"
          "pg_cron"
          "pg_net"
          "pg_stat_statements"
          "pg_tle"
          "pgaudit"
          "pgsodium"
          "plan_filter"
          "plpgsql"
          "plpgsql_check"
          "supabase_vault"
        ];
      }
      (lib.mkIf ((lib.toInt (lib.versions.major cfg.package.version)) < 16) {
        db_user_namespace = "off";
        shared_preload_libraries = [ "timescaledb" ];
      })
      self.supabase.postgres.defaults.settings
    ];

    systemd.targets.postgresql = {
      description = "PostgreSQL";
      wantedBy = [ "system-manager.target" ];
      requires = [
        "postgresql.service"
        "postgresql-setup.service"
      ];
    };

    systemd.services = {
      postgresql = {
        description = "PostgreSQL Server";

        after = [ "network.target" ];

        # To trigger the .target also on "systemctl start postgresql" as well as on
        # restarts & stops.
        # Please note that postgresql.service & postgresql.target binding to
        # each other makes the Restart=always rule racy and results
        # in sometimes the service not being restarted.
        wants = [ "postgresql.target" ];
        partOf = [ "postgresql.target" ];
        wantedBy = [ "system-manager.target" ];

        environment = {
          PGDATA = cfg.dataDir;
        }
        // cfg.environmentVariables;

        path = [ cfg.package ];

        preStart = ''
          if ! test -e ${cfg.dataDir}/PG_VERSION; then
            # Initialise the database.
            initdb ${lib.escapeShellArgs cfg.initdbArgs}
          fi
          if [ ! -f /etc/postgresql-custom/pgsodium_root.key ]; then
            umask 077
            echo "0000000000000000000000000000000000000000000000000000000000000000" > /etc/postgresql-custom/pgsodium_root.key
          fi

          # TODO postgres_prestart.sh logic here
        '';

        serviceConfig = {
          ExecReload = "${pkgs.coreutils}/bin/kill -HUP $MAINPID";
          User = "postgres";
          Group = "postgres";
          RuntimeDirectory = "postgresql";
          Type = "notify";

          # Shut down Postgres using SIGINT ("Fast Shutdown mode").  See
          # https://www.postgresql.org/docs/current/server-shutdown.html
          KillSignal = "SIGINT";
          KillMode = "mixed";

          # Give Postgres a decent amount of time to clean up after
          # receiving systemd's SIGINT.
          TimeoutSec = 120;

          ExecStart = "${cfg.package}/bin/postgres -c config_file=/etc/postgresql/postgresql.conf";

          Restart = "always";

          # Hardening
          CapabilityBoundingSet = [ "" ];
          DevicePolicy = "closed";
          PrivateTmp = true;
          ProtectHome = true;
          ProtectSystem = "strict";
          MemoryDenyWriteExecute = true; # might be a problem for plv8 ?
          NoNewPrivileges = true;
          LockPersonality = true;
          PrivateDevices = true;
          PrivateMounts = true;
          ProcSubset = "pid";
          ProtectClock = true;
          ProtectControlGroups = true;
          ProtectHostname = true;
          ProtectKernelLogs = true;
          ProtectKernelModules = true;
          ProtectKernelTunables = true;
          ProtectProc = "invisible";
          RemoveIPC = true;
          RestrictAddressFamilies = [
            "AF_INET"
            "AF_INET6"
            "AF_NETLINK" # used for network interface enumeration
            "AF_UNIX"
          ];
          RestrictNamespaces = true;
          RestrictRealtime = true;
          RestrictSUIDSGID = true;
          SystemCallArchitectures = "native";
          SystemCallFilter = [
            "@system-service"
            "~@privileged"
            "~@resources"
            "@pkey"
          ];
          UMask = "0077";
          ReadWritePaths = [
            cfg.dataDir
            "/etc/postgresql-custom"
          ];
          ReadOnlyPaths = [
            "/etc/postgresql"
          ];
        };
      };
      "setup-locales" = {
        description = "Setup locales on the system";

        before = [ "sysinit-reactivation.target" ];
        wantedBy = [ "sysinit-reactivation.target" ];

        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
          ExecStart = lib.getExe (pkgs.writeShellScriptBin "setup-locales" ''
            PATH=/usr/sbin:/usr/bin
            /usr/sbin/locale-gen
            /usr/sbin/update-locale
          '');
        };
      };
    };
  };
}
