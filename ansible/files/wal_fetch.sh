#! /usr/bin/env bash

set -euo pipefail

# Fetch the WAL file and sto
sudo -u wal-g wal-g wal-fetch $1 /tmp/$1 --config /etc/wal-g/config.json 

# Ensure WAL file is owned by the postgres Linux user
sudo chown postgres:postgres /tmp/$1

# Move file to its final destination
mv /tmp/$1 /var/lib/postgresql/data/$2
