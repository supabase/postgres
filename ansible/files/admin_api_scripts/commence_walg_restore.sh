#! /usr/bin/env bash

set -euo pipefail

backup_name=$1

# Stop database and empty it
systemctl stop postgresql
rm -rf /var/lib/postgresql/data/*

# Download base backup
wal-g backup-fetch /var/lib/postgresql/data $backup_name --config /etc/wal-g/config.json >> /var/log/wal-g/backup-fetch.log 2>&1

# Signal for PITR upon restarting the DB
touch /var/lib/postgresql/data/recovery.signal

# Ensure that downloaded backup is owned by the postgres Linux user
find /var/lib/postgresql/data/ -exec chown postgres:postgres {} +
find /var/lib/postgresql/data/ -type d -exec chmod 0750 {} +
find /var/lib/postgresql/data/ -type f -exec chmod 0640 {} +

# Enable restoration upon start
sed -i "s/#restore_command/restore_command/" /etc/postgresql-custom/wal-g.conf 

#$2 would be the value for recovery_target_time
if [ ! -z ${2+x} ]; then
    sed -i "s/.*recovery_target_time.*/recovery_target_time = '$2'/" /etc/postgresql-custom/wal-g.conf
    sed -i "s/.*recovery_target_action/recovery_target_action/" /etc/postgresql-custom/wal-g.conf
fi

# Restart the DB
systemctl start postgresql
