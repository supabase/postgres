#! /usr/bin/env bash

set -euo pipefail

STATUS_FILE="/tmp/pg-upgrade-status"

if [ -f "${STATUS_FILE}" ]; then
    STATUS=$(cat "${STATUS_FILE}")
    echo -n "${STATUS}"
else
    echo -n "unknown"
fi