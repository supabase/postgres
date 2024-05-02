#!/bin/bash
set -eou pipefail

touch "/var/log/wal-g/pitr.log"
chown postgres:postgres "/var/log/wal-g/pitr.log"
chmod 0666 "/var/log/wal-g/pitr.log"

/usr/local/bin/configure-shim.sh /dist/admin-mgr /usr/bin/admin-mgr
