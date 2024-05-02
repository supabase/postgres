#!/bin/bash
set -eou pipefail

PG_EGRESS_COLLECT_FILE=/tmp/pg_egress_collect.txt

if [ "${DATA_VOLUME_MOUNTPOINT:-}" != "" ]; then
  touch "${DATA_VOLUME_MOUNTPOINT}/pg_egress_collect.txt"
  ln -s "${DATA_VOLUME_MOUNTPOINT}/pg_egress_collect.txt" $PG_EGRESS_COLLECT_FILE
fi
