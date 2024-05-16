#!/bin/bash

# Check for occurrences of an NDisc log error
# NOTE: --since timer flag must match the cadence of systemd timer unit. Risk of repeat matches and restart loop
journalctl --no-pager --unit systemd-networkd --since "1 minutes ago" --grep "Could not set NDisc route" >/dev/null
NDISC_ERROR=$?

if systemctl is-active --quiet systemd-networkd.service && [ "${NDISC_ERROR}" == 0 ]; then
  echo "$(date) systemd-network running but NDisc routes are broken. Restarting systemd.networkd.system"
  /usr/bin/systemctl restart systemd-networkd.service
fi
