#! /usr/bin/env bash

set -euo pipefail

# Fetch the WAL file and temporarily store them in /tmp
wal-g wal-fetch "$1" /tmp/wal_fetch_dir/"$1" --config /etc/wal-g/config.json 

# Ensure WAL file is owned by the postgres Linux user
/root/wal_change_ownership.sh "$1"

# Move file to its final destination
mv /tmp/wal_fetch_dir/"$1" /var/lib/postgresql/data/"$2"
