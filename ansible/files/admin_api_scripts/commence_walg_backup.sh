#! /usr/bin/env bash

set -euo pipefail

wal-g backup-push /var/lib/postgresql/data --config /etc/wal-g/config.json --verify >> /var/log/wal-g/backup-push 2>&1

echo "WAL-G backup complete"
