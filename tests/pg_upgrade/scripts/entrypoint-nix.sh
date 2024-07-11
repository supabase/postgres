#!/bin/bash

set -e 

# Print all arguments
echo "Arguments received: $@"

# If any arguments are passed, execute them
if [ $# -gt 0 ]; then
    exec "$@"
fi

SCRIPT_DIR=$(dirname -- "$0";)

ls -la "$SCRIPT_DIR"

#tar -xzf "${SCRIPT_DIR}/pg_upgrade_scripts.tar.gz" -C "${SCRIPT_DIR}"

# mkdir -p /tmp/persistent
# cp "$SCRIPT_DIR/pg_upgrade_bin.tar.gz" /tmp/persistent

export PATH="$(pg_config --bindir):$PATH"
echo "PATH is $PATH"
whoami
gosu root sed -i "s/|--version//g" /usr/local/bin/docker-entrypoint.sh
/usr/local/bin/docker-entrypoint.sh postgres --version || true
#ls -la /data/postgresql
#ls -la /etc/postgresql
# ls -la /data/postgresql
# ls -la /etc/postgresql
# ls -la /
# ls -la /usr/lib/postgresql/bin
# echo $PGDATA
# whoami
echo "pg pass is $POSTGRES_PASSWORD"
#/bin/initdb --username="$POSTGRES_USER" --pwfile=<(printf "%s\n" "$POSTGRES_PASSWORD")  
# #cat /etc/postgresql/postgresql.conf 
# echo  "###############################################"
# ls -la /var/lib/postgresql/data
# echo  "###############################################"
#/bin/pg_ctl -D /data/postgresql start -o "-c config_file=/etc/postgresql/postgresql.conf"  -l /tmp/postgres.log -W
# /bin/postgres -D /data/postgresql -c config_file=/etc/postgresql/postgresql.conf
#gosu postgres /bin/bash -c "$(pg_config --bindir)/pg_ctl start -o '-c config_file=/etc/postgresql/postgresql.conf' -l /tmp/postgres.log"
# postgres_env_vars="export LANG=en_US.UTF-8 \
# export LANGUAGE=en_US:en \
# export LC_ALL=en_US.UTF-8 \
# export LOCALE_ARCHIVE=/usr/lib/locale/locale-archive"
#gosu postgres /bin/bash -c "$postgres_env_vars $(pg_config --bindir)/postgres -D /var/lib/postgresql/data 'config_file=/etc/postgresql/postgresql.conf'"
gosu postgres /bin/bash -c "$(pg_config --bindir)/pg_ctl start -o '-c config_file=/etc/postgresql/postgresql.conf' -l /tmp/postgres.log"
#cat /tmp/postgres.log
RECEIVED_EXIT_SIGNAL=false
trap 'RECEIVED_EXIT_SIGNAL=true' SIGINT SIGTERM SIGUSR1
while ! ((RECEIVED_EXIT_SIGNAL)); do
    sleep 5
done
