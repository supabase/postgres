#! /usr/bin/env bash

function read_replica_preparations {    
    # Clear everything beforehand
    if [[ -d /tmp/wal_fetch_dir ]]; then
        rm -rf /tmp/wal_fetch_dir
    fi
    
    mkdir /tmp/wal_fetch_dir
    chown postgres:postgres /tmp/wal_fetch_dir
    chmod 770 /tmp/wal_fetch_dir
    
    backup_name=$1
    
    # Stop database and empty it
    systemctl stop postgresql
    rm -rf /var/lib/postgresql/data/*

    # Download base backup
    wal-g backup-fetch /var/lib/postgresql/data "$backup_name" --config /etc/wal-g/config.json

    # Signal for DB to be a Read Replica upon restart
    touch /var/lib/postgresql/data/standby.signal

    # Ensure that downloaded backup is owned by the postgres Linux user
    find /var/lib/postgresql/data/ -exec chown postgres:postgres {} +
    find /var/lib/postgresql/data/ -type d -exec chmod 0750 {} +
    find /var/lib/postgresql/data/ -type f -exec chmod 0640 {} +

    # Include /etc/postgresql-custom/read-replica.conf
    # Upon restart
    sed -i "s,.*include = '/etc/postgresql-custom/read-replica.conf',include = '/etc/postgresql-custom/read-replica.conf," /etc/postgresql/postgresql.conf

    # Restart the DB
    systemctl start postgresql
}

set -euo pipefail

read_replica_preparations "$1" >> /var/log/wal-g/backup-fetch.log 2>&1 &
echo "Activation of read replica commenced"
