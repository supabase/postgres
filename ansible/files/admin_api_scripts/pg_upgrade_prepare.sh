#! /usr/bin/env bash
## This script is runs in advance of the database version upgrade, on the newly
## launched instance which will eventually be promoted to become the primary
## database instance once the upgrade successfully completes, terminating the
## previous (source) instance.
## The following commands safely stop the Postgres service and unmount
## the data disk off the newly launched instance, to be re-attached to the
## source instance and run the upgrade there.

set -euo pipefail

if [[ $(systemctl is-active gotrue) == "active" ]]; then
    echo "stopping gotrue"
    systemctl stop gotrue || true
fi

if [[ $(systemctl is-active postgrest) == "active" ]]; then
    echo "stopping postgrest"
    systemctl stop postgrest || true
fi

systemctl stop postgresql

umount /data
