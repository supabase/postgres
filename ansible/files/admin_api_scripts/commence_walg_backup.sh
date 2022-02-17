#! /usr/bin/env bash

set -euo pipefail

wal-g backup-push /var/lib/postgresql/data --config /etc/wal-g/config.json --verify

echo "WAL-G backup complete"
