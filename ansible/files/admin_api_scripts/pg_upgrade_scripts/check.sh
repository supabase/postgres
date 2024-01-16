#! /usr/bin/env bash
## This script provides a method to check the status of the database upgrade
## process, which is updated in /root/pg_upgrade/status by initiate.sh
## This runs on the old (source) instance.

set -euo pipefail

SCRIPT_DIR=$(dirname -- "$0";)
# shellcheck disable=SC1091
source "$SCRIPT_DIR/common.sh"

if [ -f "${UPGRADE_STATUS_FILE}" ]; then
    STATUS=$(cat "${UPGRADE_STATUS_FILE}")
    echo -n "${STATUS}"
else
    echo -n "unknown"
fi

