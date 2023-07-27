#! /usr/bin/env bash
set -euo pipefail
set -x

cd "$(dirname "$0")"
cat $@ > merged.conf

/usr/local/bin/shim.sh /opt/postgrest merged.conf
