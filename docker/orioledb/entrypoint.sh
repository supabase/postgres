#!/usr/bin/env bash
set -eou pipefail

PG_CONF=/etc/postgresql/postgresql.conf

function configure_orioledb {
  echo "Configuring OrioleDB..."

  sed -i \
    -e "s|#max_worker_processes = .*|max_worker_processes = 50 # should fit orioledb.s3_num_workers as long as other workers|" \
    -e "s|#log_min_messages = .*|log_min_messages = debug1 # will log all S3 requests|" \
    -e "s|#archive_mode = off\(.*\)|archive_mode = on\1|" \
    "$PG_CONF"

  echo "
archive_library = 'orioledb'
orioledb.main_buffers = 1GB
orioledb.undo_buffers = 256MB
orioledb.s3_num_workers = 20 # should be enough for comfortable work
orioledb.s3_mode = true
orioledb.s3_host = '$S3_HOST' # replace with your bucket URL, accelerated buckets are recommended
orioledb.s3_region = '$S3_REGION' # replace with your S3 region
orioledb.s3_accesskey = '$S3_ACCESS_KEY' # replace with your S3 key
orioledb.s3_secretkey = '$S3_SECRET_KEY' # replace with your S3 secret key
" >> "$PG_CONF"
}

if ! grep -q orioledb "$PG_CONF"; then
  configure_orioledb
fi

docker-entrypoint.sh "$@"
