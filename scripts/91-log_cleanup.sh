#!/bin/bash
#Erasing all logs
#
echo "Clearing all log files"
rm -rf /var/log/*

# https://github.com/fail2ban/fail2ban/issues/1593
touch /var/log/auth.log

touch /var/log/pgbouncer.log
mkdir /var/log/postgresql
chown postgres:postgres /var/log/pgbouncer.log /var/log/postgresql