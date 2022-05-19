#! /usr/bin/env bash

set -euo pipefail

sed -i "s/.*archive_mode/#archive_mode/" /etc/postgresql-custom/wal-g.conf
sed -i "s/.*archive_command/#archive_command/" /etc/postgresql-custom/wal-g.conf
sed -i "s/.*archive_timeout/#archive_timeout/" /etc/postgresql-custom/wal-g.conf

systemctl restart postgresql

echo "WAL-G successfully disabled"
