#! /usr/bin/env bash

## This script is run on the old (source) instance, mounting the data disk
## of the newly launched instance, disabling extensions containing regtypes,
## and running pg_upgrade.
## It reports the current status of the upgrade process to /tmp/pg-upgrade-status,
## which can then be subsequently checked through pg_upgrade_check.sh.

# Extensions to disable before running pg_upgrade.
# Running an upgrade with these extensions enabled will result in errors due to 
# them depending on regtypes referencing system OIDs or outdated library files. 
EXTENSIONS_TO_DISABLE=(
    "pg_graphql"
    "plv8"
    "plcoffee"
    "plls"
)

PG14_EXTENSIONS_TO_DISABLE=(
    "wrappers"
    "pgrouting"
)

PG13_EXTENSIONS_TO_DISABLE=(
    "pgrouting"
)

set -eEuo pipefail

# shellcheck disable=SC1091
source ./pg_upgrade_common.sh

LOG_FILE="/var/log/pg-upgrade-initiate.log"

PGVERSION=$1
IS_DRY_RUN=${2:-false}
if [ "$IS_DRY_RUN" != false ]; then
    IS_DRY_RUN=true
fi

MOUNT_POINT="/data_migration"

POST_UPGRADE_EXTENSION_SCRIPT="/tmp/pg_upgrade/pg_upgrade_extensions.sql"
OLD_PGVERSION=$(run_sql -A -t -c "SHOW server_version;")

# If upgrading from older major PG versions, disable specific extensions
if [[ "$OLD_PGVERSION" =~ 14* ]]; then
    EXTENSIONS_TO_DISABLE+=("${PG14_EXTENSIONS_TO_DISABLE[@]}")
fi
if [[ "$OLD_PGVERSION" =~ 13* ]]; then
    EXTENSIONS_TO_DISABLE+=("${PG13_EXTENSIONS_TO_DISABLE[@]}")
fi


cleanup() {
    UPGRADE_STATUS=${1:-"failed"}
    EXIT_CODE=${?:-0}

    if [ "$UPGRADE_STATUS" = "failed" ]; then
        echo "Upgrade job failed. Cleaning up and exiting."
    fi

    if [ -d "${MOUNT_POINT}/pgdata/pg_upgrade_output.d/" ]; then
        echo "Copying pg_upgrade output to /var/log"
        cp -R "${MOUNT_POINT}/pgdata/pg_upgrade_output.d/" /var/log/ || true
        ship_logs "$LOG_FILE" || true
        tail -n +1 /var/log/pg_upgrade_output.d/*/* > /var/log/pg_upgrade_output.d/pg_upgrade.log || true
        ship_logs "/var/log/pg_upgrade_output.d/pg_upgrade.log" || true
    fi

    if [ -L /var/lib/postgresql ]; then
        rm /var/lib/postgresql
        mv /var/lib/postgresql.bak /var/lib/postgresql
    fi

    if [ -L "/usr/share/postgresql/${PGVERSION}" ]; then
        rm "/usr/share/postgresql/${PGVERSION}"
        mv "/usr/share/postgresql/${PGVERSION}.bak" "/usr/share/postgresql/${PGVERSION}"
    fi

    if [ "$IS_DRY_RUN" = false ]; then
        echo "Restarting postgresql"
        systemctl restart postgresql
    fi

    echo "Re-enabling extensions"
    if [ -f $POST_UPGRADE_EXTENSION_SCRIPT ]; then
        run_sql -f $POST_UPGRADE_EXTENSION_SCRIPT
    fi

    echo "Removing SUPERUSER grant from postgres"
    run_sql -c "ALTER USER postgres WITH NOSUPERUSER;"

    if [ "$IS_DRY_RUN" = false ]; then
        echo "Unmounting data disk from ${MOUNT_POINT}"
        umount $MOUNT_POINT
    fi
    echo "$UPGRADE_STATUS" > /tmp/pg-upgrade-status

    exit "$EXIT_CODE"
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
    SHARED_PRELOAD_LIBRARIES=$(cat /etc/postgresql/postgresql.conf | grep shared_preload_libraries | sed "s/shared_preload_libraries = '\(.*\)'.*/\1/")

    # Wrappers officially launched in PG15; PG14 version is incompatible
    if [[ "$OLD_PGVERSION" =~ 14* ]]; then
        SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/wrappers, //")
    fi
    SHARED_PRELOAD_LIBRARIES=$(echo "$SHARED_PRELOAD_LIBRARIES" | sed "s/pg_cron, //")

    PGDATAOLD=$(cat /etc/postgresql/postgresql.conf | grep data_directory | sed "s/data_directory = '\(.*\)'.*/\1/")

    PGDATANEW="$MOUNT_POINT/pgdata"
    PG_UPGRADE_BIN_DIR="/tmp/pg_upgrade_bin/$PGVERSION"
    PGBINNEW="$PG_UPGRADE_BIN_DIR/bin"
    PGSHARENEW="$PG_UPGRADE_BIN_DIR/share"

    # running upgrade using at least 1 cpu core
    WORKERS=$(nproc | awk '{ print ($1 == 1 ? 1 : $1 - 1) }')
    
    echo "1. Extracting pg_upgrade binaries"
    mkdir -p "/tmp/pg_upgrade_bin"
    tar zxf "/tmp/persistent/pg_upgrade_bin.tar.gz" -C "/tmp/pg_upgrade_bin"

    # copy upgrade-specific pgsodium_getkey script into the share dir
    chmod +x "/root/pg_upgrade_pgsodium_getkey.sh"
    cp /root/pg_upgrade_pgsodium_getkey.sh "$PGSHARENEW/extension/pgsodium_getkey"
    if [ -d "/var/lib/postgresql/extension/" ]; then
        cp /root/pg_upgrade_pgsodium_getkey.sh "/var/lib/postgresql/extension/pgsodium_getkey"
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
    echo "3. Installing libprotobuf-c1 if missing"
    if [[ ! "$(apt list --installed libprotobuf-c1 | grep "installed")" ]]; then
        apt-get update && apt --fix-broken install -y libprotobuf-c1
    fi

    if [ "$IS_DRY_RUN" = false ]; then
        # awk NF==3 prints lines with exactly 3 fields, which are the block devices currently not mounted anywhere
        # excluding nvme0 since it is the root disk
        echo "4. Determining block device to mount"
        BLOCK_DEVICE=$(lsblk -dprno name,size,mountpoint,type | grep "disk" | grep -v "nvme0" | awk 'NF==3 { print $1; }')
        echo "Block device found: $BLOCK_DEVICE"

        mkdir -p "$MOUNT_POINT"
        echo "5. Mounting block device"

        sleep 5
        e2fsck -pf "$BLOCK_DEVICE"

        sleep 1
        mount "$BLOCK_DEVICE" "$MOUNT_POINT"

        sleep 1
        resize2fs "$BLOCK_DEVICE"
    fi

    if [ -f "$MOUNT_POINT/pgsodium_root.key" ]; then
        cp "$MOUNT_POINT/pgsodium_root.key" /etc/postgresql-custom/pgsodium_root.key
        chown postgres:postgres /etc/postgresql-custom/pgsodium_root.key
        chmod 600 /etc/postgresql-custom/pgsodium_root.key
    fi

    echo "6. Disabling extensions and generating post-upgrade script"
    handle_extensions
    
    echo "7. Granting SUPERUSER to postgres user"
    run_sql -c "ALTER USER postgres WITH SUPERUSER;"

    echo "8. Creating new data directory, initializing database"
    chown -R postgres:postgres "$MOUNT_POINT/"
    rm -rf "${PGDATANEW:?}/"
    su -c "$PGBINNEW/initdb -L $PGSHARENEW -D $PGDATANEW/" -s "$SHELL" postgres

    UPGRADE_COMMAND=$(cat <<EOF
    time ${PGBINNEW}/pg_upgrade \
    --old-bindir="/usr/lib/postgresql/bin" \
    --new-bindir=${PGBINNEW} \
    --old-datadir=${PGDATAOLD} \
    --new-datadir=${PGDATANEW} \
    --jobs="${WORKERS}" \
    --old-options='-c config_file=/etc/postgresql/postgresql.conf' \
    --old-options="-c shared_preload_libraries='${SHARED_PRELOAD_LIBRARIES}'" \
    --new-options="-c data_directory=${PGDATANEW}" \
    --new-options="-c shared_preload_libraries='${SHARED_PRELOAD_LIBRARIES}'"
EOF
    )

    if [ "$IS_DRY_RUN" = true ]; then
        UPGRADE_COMMAND="$UPGRADE_COMMAND --check"
    else 
        if [ -d "/usr/share/postgresql/${PGVERSION}" ]; then
            mv "/usr/share/postgresql/${PGVERSION}" "/usr/share/postgresql/${PGVERSION}.bak"
        fi
        ln -s "$PGSHARENEW" "/usr/share/postgresql/${PGVERSION}"

        echo "9. Stopping postgres; running pg_upgrade"
        systemctl stop postgresql
    fi

    su -c "$UPGRADE_COMMAND" -s "$SHELL" postgres

    # copying custom configurations
    echo "10. Copying custom configurations"
    mkdir -p "$MOUNT_POINT/conf"
    cp -R /etc/postgresql-custom/* "$MOUNT_POINT/conf/"

    # copy sql files generated by pg_upgrade
    echo "11. Copying sql files generated by pg_upgrade"
    mkdir -p "$MOUNT_POINT/sql"
    cp /tmp/pg_upgrade/*.sql "$MOUNT_POINT/sql/" || true
    chown -R postgres:postgres "$MOUNT_POINT/sql/"

    echo "12. Cleaning up"
    cleanup "complete"
}

trap cleanup ERR

echo "running" > /tmp/pg-upgrade-status
if [ "$IS_DRY_RUN" = true ]; then
    initiate_upgrade
else 
    initiate_upgrade >> "$LOG_FILE" 2>&1 &
    echo "Upgrade initiate job completed"
fi
