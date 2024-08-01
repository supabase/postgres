#! /usr/bin/env bash

## This script is run on the old (source) instance, mounting the data disk
## of the newly launched instance, disabling extensions containing regtypes,
## and running pg_upgrade.
## It reports the current status of the upgrade process to /tmp/pg-upgrade-status,
## which can then be subsequently checked through check.sh.

# Extensions to disable before running pg_upgrade.
# Running an upgrade with these extensions enabled will result in errors due to
# them depending on regtypes referencing system OIDs or outdated library files.
EXTENSIONS_TO_DISABLE=(
    "pg_graphql"
)

PG14_EXTENSIONS_TO_DISABLE=(
    "wrappers"
    "pgrouting"
)

PG13_EXTENSIONS_TO_DISABLE=(
    "pgrouting"
)

set -eEuo pipefail

SCRIPT_DIR=$(dirname -- "$0";)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

IS_CI=${IS_CI:-}
IS_LOCAL_UPGRADE=${IS_LOCAL_UPGRADE:-}
IS_NIX_UPGRADE=${IS_NIX_UPGRADE:-}
IS_NIX_BASED_SYSTEM="false"

PGVERSION=$1
MOUNT_POINT="/data_migration"
LOG_FILE="/var/log/pg-upgrade-initiate.log"

POST_UPGRADE_EXTENSION_SCRIPT="/tmp/pg_upgrade/pg_upgrade_extensions.sql"
OLD_PGVERSION=$(run_sql -A -t -c "SHOW server_version;")

SERVER_LC_COLLATE=$(run_sql -A -t -c "SHOW lc_collate;")
SERVER_LC_CTYPE=$(run_sql -A -t -c "SHOW lc_ctype;")
SERVER_ENCODING=$(run_sql -A -t -c "SHOW server_encoding;")

POSTGRES_CONFIG_PATH="/etc/postgresql/postgresql.conf"
PGBINOLD="/usr/lib/postgresql/bin"
PGLIBOLD="/usr/lib/postgresql/lib"

PG_UPGRADE_BIN_DIR="/tmp/pg_upgrade_bin/$PGVERSION"

if [ -L "$PGBINOLD/pg_upgrade" ]; then
    BINARY_PATH=$(readlink -f "$PGBINOLD/pg_upgrade")
    if [[ "$BINARY_PATH" == *"nix"* ]]; then
        IS_NIX_BASED_SYSTEM="true"
    fi
fi

# If upgrading from older major PG versions, disable specific extensions
if [[ "$OLD_PGVERSION" =~ ^14.* ]]; then
    EXTENSIONS_TO_DISABLE+=("${PG14_EXTENSIONS_TO_DISABLE[@]}")
elif [[ "$OLD_PGVERSION" =~ ^13.* ]]; then
    EXTENSIONS_TO_DISABLE+=("${PG13_EXTENSIONS_TO_DISABLE[@]}")
elif [[ "$OLD_PGVERSION" =~ ^12.* ]]; then
    POSTGRES_CONFIG_PATH="/etc/postgresql/12/main/postgresql.conf"
    PGBINOLD="/usr/lib/postgresql/12/bin"
fi

if [ -n "$IS_CI" ]; then
    PGBINOLD="$(pg_config --bindir)"
    echo "Running in CI mode; using pg_config bindir: $PGBINOLD"
    echo "PGVERSION: $PGVERSION"
fi

OLD_BOOTSTRAP_USER=$(run_sql -A -t -c "select rolname from pg_authid where oid = 10;")

cleanup() {
    UPGRADE_STATUS=${1:-"failed"}
    EXIT_CODE=${?:-0}

    if [ "$UPGRADE_STATUS" = "failed" ]; then
        EXIT_CODE=1
    fi

    if [ "$UPGRADE_STATUS" = "failed" ]; then
        echo "Upgrade job failed. Cleaning up and exiting."
    fi

    if [ -d "${MOUNT_POINT}/pgdata/pg_upgrade_output.d/" ]; then
        echo "Copying pg_upgrade output to /var/log"
        cp -R "${MOUNT_POINT}/pgdata/pg_upgrade_output.d/" /var/log/ || true
        chown -R postgres:postgres /var/log/pg_upgrade_output.d/
        chmod -R 0750 /var/log/pg_upgrade_output.d/
        ship_logs "$LOG_FILE" || true
        tail -n +1 /var/log/pg_upgrade_output.d/*/* > /var/log/pg_upgrade_output.d/pg_upgrade.log || true
        ship_logs "/var/log/pg_upgrade_output.d/pg_upgrade.log" || true
    fi

    if [ -L "/usr/share/postgresql/${PGVERSION}" ]; then
        rm "/usr/share/postgresql/${PGVERSION}"

        if [ -f "/usr/share/postgresql/${PGVERSION}.bak" ]; then
            mv "/usr/share/postgresql/${PGVERSION}.bak" "/usr/share/postgresql/${PGVERSION}"
        fi

        if [ -d "/usr/share/postgresql/${PGVERSION}.bak" ]; then
            mv "/usr/share/postgresql/${PGVERSION}.bak" "/usr/share/postgresql/${PGVERSION}"
        fi
    fi

    echo "Restarting postgresql"
    if [ -z "$IS_CI" ]; then
        systemctl enable postgresql
        retry 5 systemctl restart postgresql
    else
        CI_start_postgres
    fi

    echo "Re-enabling extensions"
    if [ -f $POST_UPGRADE_EXTENSION_SCRIPT ]; then
        run_sql -f $POST_UPGRADE_EXTENSION_SCRIPT
    fi

    echo "Removing SUPERUSER grant from postgres"
    run_sql -c "ALTER USER postgres WITH NOSUPERUSER;"

    if [ -z "$IS_CI" ] && [ -z "$IS_LOCAL_UPGRADE" ]; then
        echo "Unmounting data disk from ${MOUNT_POINT}"
        umount $MOUNT_POINT
    fi
    echo "$UPGRADE_STATUS" > /tmp/pg-upgrade-status

    if [ -z "$IS_CI" ]; then
        exit "$EXIT_CODE"
    else 
        echo "CI run complete with code ${EXIT_CODE}. Exiting."
        exit "$EXIT_CODE"
    fi
}

function handle_extensions {
    rm -f $POST_UPGRADE_EXTENSION_SCRIPT
    touch $POST_UPGRADE_EXTENSION_SCRIPT

    PASSWORD_ENCRYPTION_SETTING=$(run_sql -A -t -c "SHOW password_encryption;")
    if [ "$PASSWORD_ENCRYPTION_SETTING" = "md5" ]; then
        echo "ALTER SYSTEM SET password_encryption = 'md5';" >> $POST_UPGRADE_EXTENSION_SCRIPT
    fi

    cat << EOF >> $POST_UPGRADE_EXTENSION_SCRIPT
ALTER SYSTEM SET jit = off;
SELECT pg_reload_conf();
EOF

    # Disable extensions if they're enabled
    # Generate SQL script to re-enable them after upgrade
    for EXTENSION in "${EXTENSIONS_TO_DISABLE[@]}"; do
        EXTENSION_ENABLED=$(run_sql -A -t -c "SELECT EXISTS(SELECT 1 FROM pg_extension WHERE extname = '${EXTENSION}');")
        if [ "$EXTENSION_ENABLED" = "t" ]; then
            echo "Disabling extension ${EXTENSION}"
            run_sql -c "DROP EXTENSION IF EXISTS ${EXTENSION} CASCADE;"
            cat << EOF >> $POST_UPGRADE_EXTENSION_SCRIPT
DO \$\$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_available_extensions WHERE name = '${EXTENSION}') THEN
        CREATE EXTENSION IF NOT EXISTS ${EXTENSION} CASCADE;
    END IF;
END;
\$\$;
EOF
        fi
    done
}

function initiate_upgrade {
    mkdir -p "$MOUNT_POINT"
    SHARED_PRELOAD_LIBRARIES=$(cat "$POSTGRES_CONFIG_PATH" | grep shared_preload_libraries | sed "s/shared_preload_libraries =\s\{0,1\}'\(.*\)'.*/\1/")

    # Wrappers officially launched in PG15; PG14 version is incompatible
    if [[ "$OLD_PGVERSION" =~ 14* ]]; then
        SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/wrappers//" | xargs)
    fi
    SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/pg_cron//" | xargs)
    SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/pg_net//" | xargs)
    SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/check_role_membership//" | xargs)
    SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/safeupdate//" | xargs)

    # Exclude empty-string entries, as well as leading/trailing commas and spaces resulting from the above lib exclusions
    #  i.e. " , pg_stat_statements, , pgsodium, " -> "pg_stat_statements, pgsodium"
    SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | tr ',' ' ' | tr -s ' ' | tr ' ' ', ')

    # Account for trailing comma
    # eg. "...,auto_explain,pg_tle,plan_filter," -> "...,auto_explain,pg_tle,plan_filter"
    if [[ "${SHARED_PRELOAD_LIBRARIES: -1}" = "," ]]; then
        # clean up trailing comma
        SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/.$//" | xargs)
    fi

    PGDATAOLD=$(cat "$POSTGRES_CONFIG_PATH" | grep data_directory | sed "s/data_directory = '\(.*\)'.*/\1/")

    PGDATANEW="$MOUNT_POINT/pgdata"

    # running upgrade using at least 1 cpu core
    WORKERS=$(nproc | awk '{ print ($1 == 1 ? 1 : $1 - 1) }')

    # To make nix-based upgrades work for testing, create a pg binaries tarball with the following contents:
    #  - nix_flake_version - a7189a68ed4ea78c1e73991b5f271043636cf074
    # Where the value is the commit hash of the nix flake that contains the binaries

    if [ -n "$IS_LOCAL_UPGRADE" ]; then
        mkdir -p "$PG_UPGRADE_BIN_DIR"
        mkdir -p /tmp/persistent/
        echo "a7189a68ed4ea78c1e73991b5f271043636cf074" > "$PG_UPGRADE_BIN_DIR/nix_flake_version"
        tar -czf "/tmp/persistent/pg_upgrade_bin.tar.gz" -C "/tmp/pg_upgrade_bin" .
        rm -rf /tmp/pg_upgrade_bin/
    fi
    
    echo "1. Extracting pg_upgrade binaries"
    mkdir -p "/tmp/pg_upgrade_bin"
    tar zxf "/tmp/persistent/pg_upgrade_bin.tar.gz" -C "/tmp/pg_upgrade_bin"

    PGSHARENEW="$PG_UPGRADE_BIN_DIR/share"

    if [ -f "$PG_UPGRADE_BIN_DIR/nix_flake_version" ]; then
        IS_NIX_UPGRADE="true"
        NIX_FLAKE_VERSION=$(cat "$PG_UPGRADE_BIN_DIR/nix_flake_version")

        if [ "$IS_NIX_BASED_SYSTEM" = "false" ]; then
            echo "1.1. Nix is not installed; installing."

            curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm \
            --extra-conf "substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com" \
            --extra-conf "trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
        fi

        echo "1.2. Installing flake revision: $NIX_FLAKE_VERSION"
        # shellcheck disable=SC1091
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        PG_UPGRADE_BIN_DIR=$(nix build "github:supabase/postgres/${NIX_FLAKE_VERSION}#psql_15/bin" --no-link --print-out-paths --extra-experimental-features nix-command --extra-experimental-features flakes)
        PGSHARENEW="$PG_UPGRADE_BIN_DIR/share/postgresql"
    fi

    PGBINNEW="$PG_UPGRADE_BIN_DIR/bin"
    PGLIBNEW="$PG_UPGRADE_BIN_DIR/lib"

    # copy upgrade-specific pgsodium_getkey script into the share dir
    chmod +x "$SCRIPT_DIR/pgsodium_getkey.sh"
    mkdir -p "$PGSHARENEW/extension"
    cp  "$SCRIPT_DIR/pgsodium_getkey.sh" "$PGSHARENEW/extension/pgsodium_getkey"
    if [ -d "/var/lib/postgresql/extension/" ]; then
        cp  "$SCRIPT_DIR/pgsodium_getkey.sh" "/var/lib/postgresql/extension/pgsodium_getkey"
        chown postgres:postgres "/var/lib/postgresql/extension/pgsodium_getkey"
    fi

    chown -R postgres:postgres "/tmp/pg_upgrade_bin/$PGVERSION"

    # upgrade job outputs a log in the cwd; needs write permissions
    mkdir -p /tmp/pg_upgrade/
    chown -R postgres:postgres /tmp/pg_upgrade/
    cd /tmp/pg_upgrade/

    # Fixing erros generated by previous dpkg executions (package upgrades et co)
    echo "2. Fixing potential errors generated by dpkg"
    DEBIAN_FRONTEND=noninteractive dpkg --configure -a --force-confold || true # handle errors generated by dpkg

    # Needed for PostGIS, since it's compiled with Protobuf-C support now
    echo "3. Installing libprotobuf-c1 and libicu66 if missing"
    if [[ ! "$(apt list --installed libprotobuf-c1 | grep "installed")" ]]; then
        apt-get update -y
        apt --fix-broken install -y libprotobuf-c1 libicu66 || true
    fi

    echo "4. Setup locale if required"
    if ! grep -q "^en_US.UTF-8" /etc/locale.gen ; then
        echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
    fi
    if ! grep -q "^C.UTF-8" /etc/locale.gen ; then
        echo "C.UTF-8 UTF-8" >> /etc/locale.gen
    fi
    locale-gen

    if [ -z "$IS_CI" ] && [ -z "$IS_LOCAL_UPGRADE" ]; then
        # awk NF==3 prints lines with exactly 3 fields, which are the block devices currently not mounted anywhere
        # excluding nvme0 since it is the root disk
        echo "5. Determining block device to mount"
        BLOCK_DEVICE=$(lsblk -dprno name,size,mountpoint,type | grep "disk" | grep -v "nvme0" | awk 'NF==3 { print $1; }')
        echo "Block device found: $BLOCK_DEVICE"

        mkdir -p "$MOUNT_POINT"
        echo "6. Mounting block device"

        sleep 5
        e2fsck -pf "$BLOCK_DEVICE"

        sleep 1
        mount "$BLOCK_DEVICE" "$MOUNT_POINT"

        sleep 1
        resize2fs "$BLOCK_DEVICE"
    else 
        mkdir -p "$MOUNT_POINT"
    fi

    if [ -f "$MOUNT_POINT/pgsodium_root.key" ]; then
        cp "$MOUNT_POINT/pgsodium_root.key" /etc/postgresql-custom/pgsodium_root.key
        chown postgres:postgres /etc/postgresql-custom/pgsodium_root.key
        chmod 600 /etc/postgresql-custom/pgsodium_root.key
    fi

    echo "7. Disabling extensions and generating post-upgrade script"
    handle_extensions

    # TODO: Only do postgres <-> supabase_admin swap if upgrading from postgres
    # as bootstrap user to supabase_admin as bootstrap user.
    
    echo "8. TODO"
    run_sql -c "alter role postgres superuser;"
    if [ "$OLD_BOOTSTRAP_USER" = "postgres" ]; then
        run_sql -c "create role supabase_tmp login superuser;"
        psql -h localhost -U supabase_tmp -d postgres <<-EOSQL
begin;
do $$
declare
  postgres_rolpassword text := (select rolpassword from pg_authid where rolname = 'postgres');
  supabase_admin_rolpassword text := (select rolpassword from pg_authid where rolname = 'supabase_admin');
  postgres_role_settings text[] := (select setconfig from pg_db_role_setting where setdatabase = 0 and setrole = 'postgres'::regrole);
  supabase_admin_role_settings text[] := (select setconfig from pg_db_role_setting where setdatabase = 0 and setrole = 'supabase_admin'::regrole);
  schemas oid[] := (select coalesce(array_agg(oid), '{}') from pg_namespace where nspowner = 'postgres'::regrole);
  types oid[] := (
    select coalesce(array_agg(t.oid), '{}')
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    join pg_authid a on a.oid = t.typowner
    where true
      and n.nspname != 'information_schema'
      and not starts_with(n.nspname, 'pg_')
      and a.rolname = 'postgres'
      and (
        t.typrelid = 0
        or (
          select
            c.relkind = 'c'
          from
            pg_class c
          where
            c.oid = t.typrelid
        )
      )
      and not exists (
        select
        from
          pg_type el
        where
          el.oid = t.typelem
          and el.typarray = t.oid
      )
  );
  routines oid[] := (
    select coalesce(array_agg(p.oid), '{}')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_authid a on a.oid = p.proowner
    where true
      and n.nspname != 'information_schema'
      and not starts_with(n.nspname, 'pg_')
      and a.rolname = 'postgres'
  );
  relations oid[] := (
    select coalesce(array_agg(c.oid), '{}')
    from pg_class c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_authid a on a.oid = c.relowner
    where true
      and n.nspname != 'information_schema'
      and not starts_with(n.nspname, 'pg_')
      and a.rolname = 'postgres'
      and c.relkind not in ('c', 'i')
  );
  rec record;
  objid oid;
begin
  set local search_path = '';

  alter role postgres rename to supabase_admin_;
  alter role supabase_admin rename to postgres;
  alter role supabase_admin_ rename to supabase_admin;

  -- role grants
  for rec in
    select * from pg_auth_members where member = 'supabase_admin'::regrole
  loop
    execute(format('revoke %I from supabase_admin;', rec.roleid::regrole));
    execute(format('grant %I to postgres;', rec.roleid::regrole));
  end loop;

  -- role passwords
  execute(format('alter role postgres password %L;', postgres_rolpassword));
  execute(format('alter role supabase_admin password %L;', supabase_admin_rolpassword));

  -- role settings
  -- TODO: don't modify system catalog directly
  update pg_db_role_setting set setconfig = postgres_role_settings where setdatabase = 0 and setrole = 'postgres'::regrole;
  update pg_db_role_setting set setconfig = supabase_admin_role_settings where setdatabase = 0 and setrole = 'supabase_admin'::regrole;

  reassign owned by postgres to supabase_admin;

  -- databases
  for rec in
    select * from pg_database where datname not in ('template0')
  loop
    execute(format('alter database %I owner to postgres;', rec.datname));
  end loop;

  -- publications
  for rec in
    select * from pg_publication
  loop
    execute(format('alter publication %I owner to postgres;', rec.pubname));
  end loop;

  -- FDWs
  for rec in
    select * from pg_foreign_data_wrapper
  loop
    execute(format('alter foreign data wrapper %I owner to postgres;', rec.fdwname));
  end loop;

  -- foreign servers
  for rec in
    select * from pg_foreign_server
  loop
    execute(format('alter server %I owner to postgres;', rec.srvname));
  end loop;

  -- user mappings
  -- TODO: don't modify system catalog directly
  update pg_user_mapping set umuser = 'postgres'::regrole where umuser = 'supabase_admin'::regrole;

  -- default acls
  -- TODO: don't modify system catalog directly
  update pg_default_acl set defaclrole = 0 where defaclrole = 'postgres'::regrole;
  update pg_default_acl set defaclrole = 'postgres'::regrole where defaclrole = 'supabase_admin'::regrole;
  update pg_default_acl set defaclrole = 'supabase_admin'::regrole where defaclrole = 0;

  -- schemas
  foreach objid in array schemas
  loop
    execute(format('alter schema %I owner to postgres;', objid::regnamespace));
  end loop;

  -- types
  foreach objid in array types
  loop
    execute(format('alter type %I owner to postgres;', objid::regtype));
  end loop;

  -- functions
  for rec in
    select * from pg_proc where oid = any(routines)
  loop
    execute(format('alter routine %I.%I(%s) owner to postgres;', rec.pronamespace::regnamespace, rec.proname, pg_get_function_identity_arguments(rec.oid)));
  end loop;

  -- relations
  for rec in
    select * from pg_class where oid = any(relations)
  loop
    execute(format('alter table %I.%I owner to postgres;', rec.relnamespace::regnamespace, rec.relname));
  end loop;
end
$$;
rollback;
EOSQL
        run_sql -c "drop role supabase_tmp;"
    fi

    if [ -z "$IS_NIX_UPGRADE" ]; then
        if [ -d "/usr/share/postgresql/${PGVERSION}" ]; then
            mv "/usr/share/postgresql/${PGVERSION}" "/usr/share/postgresql/${PGVERSION}.bak"
        fi

        ln -s "$PGSHARENEW" "/usr/share/postgresql/${PGVERSION}"
        cp --remove-destination "$PGLIBNEW"/*.control "$PGSHARENEW/extension/"
        cp --remove-destination "$PGLIBNEW"/*.sql "$PGSHARENEW/extension/"

        export LD_LIBRARY_PATH="${PGLIBNEW}"
    fi

    # This is a workaround for older versions of wrappers which don't have the expected
    #  naming scheme, containing the version in their library's file name
    #  e.g. wrappers-0.1.16.so, rather than wrappers.so
    # pg_upgrade errors out when it doesn't find an equivalent file in the new PG version's
    #  library directory, so we're making sure the new version has the expected (old version's)
    #  file name.
    # After the upgrade completes, the new version's library file is used.
    # i.e. 
    #  - old version: wrappers-0.1.16.so
    #  - new version: wrappers-0.1.18.so
    #  - workaround to make pg_upgrade happy: copy wrappers-0.1.18.so to wrappers-0.1.16.so
    if [ -d "$PGLIBOLD" ]; then
        WRAPPERS_LIB_PATH=$(find "$PGLIBNEW" -name "wrappers*so" -print -quit)
        if [ -f "$WRAPPERS_LIB_PATH" ]; then
            OLD_WRAPPER_LIB_PATH=$(find "$PGLIBOLD" -name "wrappers*so" -print -quit)
            if [ -f "$OLD_WRAPPER_LIB_PATH" ]; then
                LIB_FILE_NAME=$(basename "$OLD_WRAPPER_LIB_PATH")
                if [ "$WRAPPERS_LIB_PATH" != "$PGLIBNEW/${LIB_FILE_NAME}" ]; then
                    echo "Copying $OLD_WRAPPER_LIB_PATH to $WRAPPERS_LIB_PATH"
                    cp "$WRAPPERS_LIB_PATH" "$PGLIBNEW/${LIB_FILE_NAME}"
                fi
            fi
        fi
    fi

    echo "9. Creating new data directory, initializing database"
    chown -R postgres:postgres "$MOUNT_POINT/"
    rm -rf "${PGDATANEW:?}/"

    if [ "$IS_NIX_UPGRADE" = "true" ]; then
        LC_ALL=en_US.UTF-8 LC_CTYPE=$SERVER_LC_CTYPE LC_COLLATE=$SERVER_LC_COLLATE LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -c ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && $PGBINNEW/initdb --encoding=$SERVER_ENCODING --lc-collate=$SERVER_LC_COLLATE --lc-ctype=$SERVER_LC_CTYPE -L $PGSHARENEW -D $PGDATANEW/ --username=supabase_admin" -s "$SHELL" postgres
    else
        su -c "$PGBINNEW/initdb -L $PGSHARENEW -D $PGDATANEW/ --username=supabase_admin" -s "$SHELL" postgres
    fi

    # TODO: Make this declarative, replace file with the most up to date content
    # of pg_hba.conf.j2. Otherwise we'd need to supply the password for
    # supabase_admin, because pg_upgrade connects to the db as supabase_admin
    # using unix sockets, which is gated behind scram-sha-256 per the current
    # pg_hba.conf.j2.
    echo "local all all trust
$(cat /etc/postgresql/pg_hba.conf)" > /etc/postgresql/pg_hba.conf
    run_sql -c "select pg_reload_conf();"

    UPGRADE_COMMAND=$(cat <<EOF
    time ${PGBINNEW}/pg_upgrade \
    --old-bindir="${PGBINOLD}" \
    --new-bindir=${PGBINNEW} \
    --old-datadir=${PGDATAOLD} \
    --new-datadir=${PGDATANEW} \
    --username=supabase_admin \
    --jobs="${WORKERS}" -r \
    --old-options='-c config_file=${POSTGRES_CONFIG_PATH}' \
    --old-options="-c shared_preload_libraries='${SHARED_PRELOAD_LIBRARIES}'" \
    --new-options="-c data_directory=${PGDATANEW}" \
    --new-options="-c shared_preload_libraries='${SHARED_PRELOAD_LIBRARIES}'"
EOF
    )

    if [ "$IS_NIX_BASED_SYSTEM" = "true" ]; then
        UPGRADE_COMMAND=". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && $UPGRADE_COMMAND"
    fi 
    LC_ALL=en_US.UTF-8 LC_CTYPE=$SERVER_LC_CTYPE LC_COLLATE=$SERVER_LC_COLLATE LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -pc "$UPGRADE_COMMAND --check" -s "$SHELL" postgres

    echo "10. Stopping postgres; running pg_upgrade"
    # Extra work to ensure postgres is actually stopped
    #  Mostly needed for PG12 projects with odd systemd unit behavior
    if [ -z "$IS_CI" ]; then
        retry 5 systemctl restart postgresql
        systemctl disable postgresql
        retry 5 systemctl stop postgresql

        sleep 3
        systemctl stop postgresql
    else
        CI_stop_postgres
    fi

    LC_ALL=en_US.UTF-8 LC_CTYPE=$SERVER_LC_CTYPE LC_COLLATE=$SERVER_LC_COLLATE LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -pc "$UPGRADE_COMMAND" -s "$SHELL" postgres

    # copying custom configurations
    echo "11. Copying custom configurations"
    mkdir -p "$MOUNT_POINT/conf"
    cp -R /etc/postgresql-custom/* "$MOUNT_POINT/conf/"
    # removing supautils config as to allow the latest one provided by the latest image to be used
    rm -f "$MOUNT_POINT/conf/supautils.conf" || true

    # removing wal-g config as to allow it to be explicitly enabled on the new instance
    rm -f "$MOUNT_POINT/conf/wal-g.conf"

    # copy sql files generated by pg_upgrade
    echo "12. Copying sql files generated by pg_upgrade"
    mkdir -p "$MOUNT_POINT/sql"
    cp /tmp/pg_upgrade/*.sql "$MOUNT_POINT/sql/" || true
    chown -R postgres:postgres "$MOUNT_POINT/sql/"

    echo "13. Cleaning up"
    cleanup "complete"
}

trap cleanup ERR

echo "running" > /tmp/pg-upgrade-status
if [ -z "$IS_CI" ] && [ -z "$IS_LOCAL_UPGRADE" ]; then
    initiate_upgrade >> "$LOG_FILE" 2>&1 &
    echo "Upgrade initiate job completed"
else
    rm -f /tmp/pg-upgrade-status
    initiate_upgrade
fi
