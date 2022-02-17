#! /usr/bin/env bash

set -euo pipefail

backup_name=$1
recovery_target_time=$2

systemctl stop postgresql
rm -rf /var/lib/postgresql/data

wal-g backup-fetch /var/lib/postgresql/data $backup_name --config /etc/wal-g/config.json

# Enable restoration upon start
sed -i "s/#restore_command/restore_command/" /etc/postgresql/postgresql.conf

if [ ! -z ${recovery_target_time+x} ]; then 
    sed -i "s/#recovery_target_time = ''/recovery_target_time = '$recovery_target_time'/" /etc/postgresql/postgresql.conf
    sed -i "s/#recovery_target_action/recovery_target_action/" /etc/postgresql/postgresql.conf
fi

touch /var/lib/postgresql/data/recovery.signal
systemctl start postgresql

echo "WAL-G restoration complete"
