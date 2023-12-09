#!/usr/bin/env bash
set -eou pipefail

PG_CONF=/etc/postgresql/postgresql.conf

if [ "${S3_ENABLED:-}" == "true" ]; then
  echo "Enabling OrioleDB S3 Backend..."

  echo "
archive_mode = on
archive_library = 'orioledb'
max_worker_processes = 50 # should fit orioledb.s3_num_workers as long as other workers
orioledb.s3_num_workers = 20 # should be enough for comfortable work
orioledb.s3_mode = true
orioledb.s3_host = '$S3_HOST' # replace with your bucket URL, accelerated buckets are recommended
orioledb.s3_region = '$S3_REGION' # replace with your S3 region
orioledb.s3_accesskey = '$S3_ACCESS_KEY' # replace with your S3 key
orioledb.s3_secretkey = '$S3_SECRET_KEY' # replace with your S3 secret key
" >> "$PG_CONF"
else
  echo "Disabling OrioleDB S3 Backend..."

  sed -i \
    -e "/^archive_mode = on/d" \
    -e "/^archive_library = 'orioledb'/d" \
    -e "/^max_worker_processes = 50/d" \
    -e "/^orioledb.s3_num_workers = /d" \
    -e "/^orioledb.s3_mode = /d" \
    -e "/^orioledb.s3_host = /d" \
    -e "/^orioledb.s3_region = /d" \
    -e "/^orioledb.s3_accesskey = /d" \
    -e "/^orioledb.s3_secretkey = /d" \
    "$PG_CONF"
fi

orioledb-entrypoint.sh "$@"
