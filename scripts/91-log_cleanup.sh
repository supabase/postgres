#!/bin/bash
#Erasing all logs
#
echo "Clearing all log files"
rm -rf /var/log/*

# https://github.com/fail2ban/fail2ban/issues/1593
touch /var/log/auth.log

touch /var/log/pgbouncer.log
chown pgbouncer:postgres /var/log/pgbouncer.log

mkdir /var/log/postgresql
chown postgres:postgres /var/log/postgresql

mkdir /var/log/wal-g
cd /var/log/wal-g
touch backup-push.log backup-fetch.log wal-push.log wal-fetch.log
chown -R postgres:postgres /var/log/wal-g
chmod -R 0300 /var/log/wal-g
