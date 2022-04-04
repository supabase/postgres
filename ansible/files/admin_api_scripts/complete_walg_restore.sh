#! /usr/bin/env bash

set -euo pipefail

# disable 169.254.169.254 for postgres
sed -i "/#\\sdon't\\sdelete\\sthe\\s'COMMIT'/ i -I OUTPUT 1 --proto tcp --destination 169.254.169.254 --match owner --uid-owner postgres --jump REJECT\\n" /etc/ufw/before.rules
ufw reload

# move config file to its final location and change its ownership
mv /etc/postgresql/wal-g-config.json /etc/wal-g/config.json
chown wal-g:wal-g /etc/wal-g/config.json


# disable recovery commands in the event of a restart
sed -i "s/.*restore_command/#restore_command/" /etc/postgresql-custom/wal-g.conf
sed -i "s/.*recovery_target_time/#recovery_target_time/" /etc/postgresql-custom/wal-g.conf
sed -i "s/.*recovery_target_action/#recovery_target_action/" /etc/postgresql-custom/wal-g.conf

# enable archive_command
sed -i "s/.*archive_mode/archive_mode/" /etc/postgresql-custom/wal-g.conf
sed -i "s/.*archive_command/archive_command/" /etc/postgresql-custom/wal-g.conf
sed -i "s/.*archive_timeout/archive_timeout/" /etc/postgresql-custom/wal-g.conf

systemctl restart postgresql

echo "Cleanup post WAL-G restoration complete"
