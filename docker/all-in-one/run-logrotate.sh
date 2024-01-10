#!/bin/bash

set -eou pipefail

while true; do
  sleep 1800
  /usr/sbin/logrotate /etc/logrotate.conf --state "${DATA_VOLUME_MOUNTPOINT}/etc/logrotate/logrotate.state" --verbose
done
