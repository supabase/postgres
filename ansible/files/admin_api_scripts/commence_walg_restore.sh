#! /usr/bin/env bash

function commence_walg_restore {    
    # Clear everything beforehand
    if [[ -d /tmp/wal_fetch_dir ]]; then
        rm -rf /tmp/wal_fetch_dir
    fi
    
    mkdir /tmp/wal_fetch_dir
    chown postgres:postgres /tmp/wal_fetch_dir
    chmod 770 /tmp/wal_fetch_dir
    
    backup_name=$1
    recovery_target_time=$2

    echo "$recovery_target_time"
    
    # Stop database and empty it
    systemctl stop postgresql
    rm -rf /var/lib/postgresql/data/*

    # Download base backup
    wal-g backup-fetch /var/lib/postgresql/data "$backup_name" --config /etc/wal-g/config.json

    # Signal for PITR upon restarting the DB
    touch /var/lib/postgresql/data/recovery.signal

    # Ensure that downloaded backup is owned by the postgres Linux user
    find /var/lib/postgresql/data/ -exec chown postgres:postgres {} +
    find /var/lib/postgresql/data/ -type d -exec chmod 0750 {} +
    find /var/lib/postgresql/data/ -type f -exec chmod 0640 {} +

    # Enable restoration upon start
    sed -i "s/#restore_command/restore_command/" /etc/postgresql-custom/wal-g.conf 

    # Set up parameters for PITR
    sed -i "s/.*recovery_target_time =.*/recovery_target_time = '$recovery_target_time'/" /etc/postgresql-custom/wal-g.conf
    sed -i "s/.*recovery_target_action/recovery_target_action/" /etc/postgresql-custom/wal-g.conf
    sed -i "s/.*recovery_target_timeline/recovery_target_timeline/" /etc/postgresql-custom/wal-g.conf
    sed -i "s/.*recovery_target_inclusive/recovery_target_inclusive/" /etc/postgresql-custom/wal-g.conf

    # Restart the DB
    systemctl start postgresql
}

set -euo pipefail

commence_walg_restore "$1" "$2" >> /var/log/wal-g/backup-fetch.log 2>&1 &
echo "WAL-G restore job commenced"
