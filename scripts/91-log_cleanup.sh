#!/bin/bash
#Erasing all logs
#
echo "Clearing all log files"
rm -rf /var/log/*

# creating system stats directory 
/usr/sbin/service  sysstat stop >> ~/varlog2rc8.log
/usr/bin/rm -rfv /var/log/sysstat >> ~/varlog2rc8.log
/usr/bin/mkdir /var/log/sysstat >> ~/varlog2rc8.log
/usr/sbin/service sysstat start >> ~/varlog2rc8.log
/usr/bin/ls -alh /var/log/ >> ~/varlog2rc8.log
/usr/bin/sar -A >> ~/varlog2rc8.log

# https://github.com/fail2ban/fail2ban/issues/1593
touch /var/log/auth.log

touch /var/log/pgbouncer.log
chown pgbouncer:postgres /var/log/pgbouncer.log

mkdir /var/log/postgresql
chown postgres:postgres /var/log/postgresql

mkdir /var/log/wal-g
cd /var/log/wal-g
touch backup-push.log backup-fetch.log wal-push.log wal-fetch.log pitr.log
chown -R postgres:postgres /var/log/wal-g
chmod -R 0300 /var/log/wal-g

