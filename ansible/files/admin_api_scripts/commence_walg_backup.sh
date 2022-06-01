#! /usr/bin/env bash

set -euo pipefail

WALG_SENTINEL_USER_DATA="{ \"project_id\": $1, \"backup_id\": $2 }" nohup wal-g backup-push /var/lib/postgresql/data --config /etc/wal-g/config.json --verify >> /var/log/wal-g/backup-push.log 2>&1 &

echo "WAL-G backup job commenced"
