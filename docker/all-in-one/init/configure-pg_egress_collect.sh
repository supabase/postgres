#!/bin/bash
set -eou pipefail

PG_EGRESS_COLLECT_FILE=/tmp/pg_egress_collect.txt

if [ "${DATA_VOLUME_MOUNTPOINT:-}" != "" ]; then
  if [ ! -L $PG_EGRESS_COLLECT_FILE ]; then
    if [ -f $PG_EGRESS_COLLECT_FILE ]; then
      rm -f $PG_EGRESS_COLLECT_FILE
    fi
    touch "${DATA_VOLUME_MOUNTPOINT}/pg_egress_collect.txt"
    ln -s "${DATA_VOLUME_MOUNTPOINT}/pg_egress_collect.txt" $PG_EGRESS_COLLECT_FILE
  fi
fi
