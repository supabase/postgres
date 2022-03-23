#! /usr/bin/env bash

set -euo pipefail

sed -i "s/.*archive_mode/archive_mode/" /etc/postgresql/postgresql.conf
sed -i "s/.*archive_command/archive_command/" /etc/postgresql/postgresql.conf
sed -i "s/.*archive_timeout/archive_timeout/" /etc/postgresql/postgresql.conf

systemctl restart postgresql

echo "WAL-G successfully enabled"
