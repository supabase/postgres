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
    "pg_stat_monitor"
    "pg_backtrace"
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
POST_UPGRADE_POSTGRES_PERMS_SCRIPT="/tmp/pg_upgrade/pg_upgrade_postgres_perms.sql"
OLD_PGVERSION=$(run_sql -A -t -c "SHOW server_version;")

# Skip locale settings if both versions are PostgreSQL 16+
if ! [[ "${OLD_PGVERSION%%.*}" -ge 16 && "${PGVERSION%%.*}" -ge 16 ]]; then
    SERVER_LC_COLLATE=$(run_sql -A -t -c "SHOW lc_collate;")
    SERVER_LC_CTYPE=$(run_sql -A -t -c "SHOW lc_ctype;")
fi

SERVER_ENCODING=$(run_sql -A -t -c "SHOW server_encoding;")

POSTGRES_CONFIG_PATH="/etc/postgresql/postgresql.conf"
PGBINOLD="/usr/lib/postgresql/bin"

PG_UPGRADE_BIN_DIR="/tmp/pg_upgrade_bin/$PGVERSION"
NIX_INSTALLER_PATH="/tmp/persistent/nix-installer"
NIX_INSTALLER_PACKAGE_PATH="$NIX_INSTALLER_PATH.tar.gz"

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

    retry 8 pg_isready -h localhost -U supabase_admin

    echo "Re-enabling extensions"
    if [ -f $POST_UPGRADE_EXTENSION_SCRIPT ]; then
        retry 5 run_sql -f $POST_UPGRADE_EXTENSION_SCRIPT
    fi

    echo "Removing SUPERUSER grant from postgres"
    retry 5 run_sql -c "ALTER USER postgres WITH NOSUPERUSER;"

    echo "Resetting postgres database connection limit"
    retry 5 run_sql -c "ALTER DATABASE postgres CONNECTION LIMIT -1;"

    echo "Making sure postgres still has access to pg_shadow"
    cat << EOF >> $POST_UPGRADE_POSTGRES_PERMS_SCRIPT
DO \$\$
begin
  if exists (select from pg_authid where rolname = 'pg_read_all_data') then
    execute('grant pg_read_all_data to postgres');
  end if;
end
\$\$;
grant pg_signal_backend to postgres;
EOF

    if [ -f $POST_UPGRADE_POSTGRES_PERMS_SCRIPT ]; then
        retry 5 run_sql -f $POST_UPGRADE_POSTGRES_PERMS_SCRIPT
    fi

    if [ -z "$IS_CI" ] && [ -z "$IS_LOCAL_UPGRADE" ]; then
        echo "Unmounting data disk from ${MOUNT_POINT}"
        retry 3 umount $MOUNT_POINT
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
    if [ -z "$IS_CI" ]; then
        retry 5 systemctl restart postgresql
    else
        CI_start_postgres
    fi

    retry 8 pg_isready -h localhost -U supabase_admin

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

    # Timescale is no longer supported for PG17+ upgrades
    if [[ "$PGVERSION" != "15" ]]; then
        SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/timescaledb//" | xargs)
    fi
    
    SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/pg_cron//" | xargs)
    SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/pg_net//" | xargs)
    SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/check_role_membership//" | xargs)
    SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/safeupdate//" | xargs)
    SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/pg_backtrace//" | xargs)

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
	if [ -n "$NIX_FLAKE_VERSION" ]; then
            echo "$NIX_FLAKE_VERSION" > "$PG_UPGRADE_BIN_DIR/nix_flake_version"
        else
            echo "a7189a68ed4ea78c1e73991b5f271043636cf074" > "$PG_UPGRADE_BIN_DIR/nix_flake_version"
        fi

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
            if [ ! -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then            
                if ! command -v nix > /dev/null; then
                    echo "1.1. Nix is not installed; installing."

                    if [ -f "$NIX_INSTALLER_PACKAGE_PATH" ]; then
                        echo "1.1.1. Installing Nix using the provided installer"
                        tar -xzf "$NIX_INSTALLER_PACKAGE_PATH" -C /tmp/persistent/
                        chmod +x "$NIX_INSTALLER_PATH"
                        "$NIX_INSTALLER_PATH" install --no-confirm \
                        --extra-conf "substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com" \
                        --extra-conf "trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                    else
                        echo "1.1.1. Installing Nix using the official installer"

                        curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install --no-confirm \
                        --extra-conf "substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com" \
                        --extra-conf "trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
                    fi
                else 
                    echo "1.1. Nix is installed; moving on."
                fi
            fi
        fi

        echo "1.2. Installing flake revision: $NIX_FLAKE_VERSION"
        # shellcheck disable=SC1091
        source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
        nix-collect-garbage -d > /tmp/pg_upgrade-nix-gc.log 2>&1 || true
        PG_UPGRADE_BIN_DIR=$(nix build "github:supabase/postgres/${NIX_FLAKE_VERSION}#psql_${PGVERSION}/bin" --no-link --print-out-paths --extra-experimental-features nix-command --extra-experimental-features flakes)
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

    echo "8.1. Granting SUPERUSER to postgres user"
    run_sql -c "ALTER USER postgres WITH SUPERUSER;"

    if [ "$OLD_BOOTSTRAP_USER" = "postgres" ]; then
        echo "8.2. Swap postgres & supabase_admin roles as we're upgrading a project with postgres as bootstrap user"
        swap_postgres_and_supabase_admin
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

    echo "9. Creating new data directory, initializing database"
    chown -R postgres:postgres "$MOUNT_POINT/"
    rm -rf "${PGDATANEW:?}/"

    if [ "$IS_NIX_UPGRADE" = "true" ]; then
        if [[ "${PGVERSION%%.*}" -ge 16 ]]; then
            LC_ALL=en_US.UTF-8 LC_CTYPE=en_US.UTF-8 LC_COLLATE=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -c ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && $PGBINNEW/initdb --encoding=$SERVER_ENCODING --locale-provider=icu --icu-locale=en_US.UTF-8 -L $PGSHARENEW -D $PGDATANEW/ --username=supabase_admin" -s "$SHELL" postgres
        else
            LC_ALL=en_US.UTF-8 LC_CTYPE=$SERVER_LC_CTYPE LC_COLLATE=$SERVER_LC_COLLATE LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -c ". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && $PGBINNEW/initdb --encoding=$SERVER_ENCODING --lc-collate=$SERVER_LC_COLLATE --lc-ctype=$SERVER_LC_CTYPE -L $PGSHARENEW -D $PGDATANEW/ --username=supabase_admin" -s "$SHELL" postgres
        fi
    else
        su -c "$PGBINNEW/initdb -L $PGSHARENEW -D $PGDATANEW/ --username=supabase_admin" -s "$SHELL" postgres

    fi

    # This line avoids the need to supply the supabase_admin password on the old
    # instance, since pg_upgrade connects to the db as supabase_admin using unix
    # sockets, which is gated behind scram-sha-256 per pg_hba.conf.j2. The new
    # instance is unaffected.
    if ! grep -q "local all supabase_admin trust" /etc/postgresql/pg_hba.conf; then
        echo "local all supabase_admin trust
$(cat /etc/postgresql/pg_hba.conf)" > /etc/postgresql/pg_hba.conf
        run_sql -c "select pg_reload_conf();"
    fi

    TMP_CONFIG="/tmp/pg_upgrade/postgresql.conf"
    cp "$POSTGRES_CONFIG_PATH" "$TMP_CONFIG"
 
    # Check if max_slot_wal_keep_size exists in the config
       # Add the setting if not found
    echo "max_slot_wal_keep_size = -1" >> "$TMP_CONFIG"

    # Remove db_user_namespace if upgrading from PG15 or lower to PG16+
    if [[ "${OLD_PGVERSION%%.*}" -le 15 && "${PGVERSION%%.*}" -ge 16 ]]; then
        sed -i '/^db_user_namespace/d' "$TMP_CONFIG"
    fi

    chown postgres:postgres "$TMP_CONFIG"
 
    UPGRADE_COMMAND=$(cat <<EOF
    time ${PGBINNEW}/pg_upgrade \
    --old-bindir="${PGBINOLD}" \
    --new-bindir=${PGBINNEW} \
    --old-datadir=${PGDATAOLD} \
    --new-datadir=${PGDATANEW} \
    --username=supabase_admin \
    --jobs="${WORKERS}" -r \
    --old-options="-c config_file=$TMP_CONFIG" \
    --old-options="-c shared_preload_libraries='${SHARED_PRELOAD_LIBRARIES}'" \
    --new-options="-c data_directory=${PGDATANEW}" \
    --new-options="-c config_file=$TMP_CONFIG" \
    --new-options="-c shared_preload_libraries='${SHARED_PRELOAD_LIBRARIES}'"
EOF
    )

    if [ "$IS_NIX_BASED_SYSTEM" = "true" ]; then
        UPGRADE_COMMAND=". /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && $UPGRADE_COMMAND"
    fi 

    if [[ "${PGVERSION%%.*}" -ge 16 ]]; then
        GRN_PLUGINS_DIR=/var/lib/postgresql/.nix-profile/lib/groonga/plugins LC_ALL=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -pc "$UPGRADE_COMMAND --check" -s "$SHELL" postgres
    else
        GRN_PLUGINS_DIR=/var/lib/postgresql/.nix-profile/lib/groonga/plugins LC_ALL=en_US.UTF-8 LC_CTYPE=$SERVER_LC_CTYPE LC_COLLATE=$SERVER_LC_COLLATE LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -pc "$UPGRADE_COMMAND --check" -s "$SHELL" postgres
    fi

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

    # Start the old PostgreSQL instance with version-specific options
    if [[ "${PGVERSION%%.*}" -ge 16 ]]; then
        GRN_PLUGINS_DIR=/var/lib/postgresql/.nix-profile/lib/groonga/plugins LC_ALL=en_US.UTF-8 LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -pc "$UPGRADE_COMMAND" -s "$SHELL" postgres
    else
        GRN_PLUGINS_DIR=/var/lib/postgresql/.nix-profile/lib/groonga/plugins LC_ALL=en_US.UTF-8 LC_CTYPE=$SERVER_LC_CTYPE LC_COLLATE=$SERVER_LC_COLLATE LANGUAGE=en_US.UTF-8 LANG=en_US.UTF-8 LOCALE_ARCHIVE=/usr/lib/locale/locale-archive su -pc "$UPGRADE_COMMAND" -s "$SHELL" postgres
    fi

    # copying custom configurations
    echo "11. Copying custom configurations"
    mkdir -p "$MOUNT_POINT/conf"
    cp -R /etc/postgresql-custom/* "$MOUNT_POINT/conf/"
    # removing supautils config as to allow the latest one provided by the latest image to be used
    rm -f "$MOUNT_POINT/conf/supautils.conf" || true
    rm -rf "$MOUNT_POINT/conf/extension-custom-scripts" || true

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
