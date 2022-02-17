#! /usr/bin/env bash

set -euo pipefail

sed -i "s/restore_command/#restore_command/" /etc/postgresql/postgresql.conf
sed -i "s/recovery_target_time/#recovery_target_time/" /etc/postgresql/postgresql.conf
sed -i "s/recovery_target_action/#recovery_target_action/" /etc/postgresql/postgresql.conf

echo "WAL-G restoration disabled for future restarts"
