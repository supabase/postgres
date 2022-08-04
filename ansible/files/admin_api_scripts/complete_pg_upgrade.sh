#! /usr/bin/env bash

set -euo pipefail

mount -a -v

# copying custom configurations
cp /data/conf/* /etc/postgresql-custom/

service postgresql start
vacuumdb --all --analyze-in-stages
