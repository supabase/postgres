#! /usr/bin/env bash

set -euo pipefail

WALG_SENTINEL_USER_DATA="{ \"backup_id\": $1, \"project_id\": $2 }" nohup wal-g backup-push /var/lib/postgresql/data --config /etc/wal-g/config.env --verify >> /var/log/wal-g/backup-push 2>&1 &

echo "WAL-G backup job commenced"