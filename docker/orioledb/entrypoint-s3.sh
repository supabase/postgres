#!/usr/bin/env bash
set -eou pipefail

echo "Configuring OrioleDB..."

sed -i \
  -e "s|^\(orioledb.s3_host\) = .*|\1 = '$S3_HOST'|" \
  -e "s|^\(orioledb.s3_region\) = .*|\1 = '$S3_REGION'|" \
  -e "s|^\(orioledb.s3_accesskey\) = .*|\1 = '$S3_ACCESS_KEY'|" \
  -e "s|^\(orioledb.s3_secretkey\) = .*|\1 = '$S3_SECRET_KEY'|" \
  "$PG_CONF"

# initdb "$PGDATA" --no-locale
docker-entrypoint.sh "$@"
