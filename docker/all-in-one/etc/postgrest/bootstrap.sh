#! /usr/bin/env bash
set -euo pipefail
set -x

cd "$(dirname "$0")"
cat $@ > merged.conf

/opt/postgrest merged.conf
