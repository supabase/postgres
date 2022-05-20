#! /usr/bin/env bash

set -euo pipefail

# Disable recovery commands in the event of a restart
sed -i "s/.*restore_command/#restore_command/" /etc/postgresql-custom/wal-g.conf
sed -i "s/.*recovery_target_time/#recovery_target_time/" /etc/postgresql-custom/wal-g.conf
sed -i "s/.*recovery_target_action/#recovery_target_action/" /etc/postgresql-custom/wal-g.conf
sed -i "s/.*recovery_target_timeline/#recovery_target_timeline/" /etc/postgresql-custom/wal-g.conf

# Cleanup /tmp
rm -rf /tmp/walg_data/ /tmp/.wal-g/

echo "Cleanup post WAL-G restoration complete"
