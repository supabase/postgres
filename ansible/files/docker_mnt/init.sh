cat /etc/postgresql/postgresql.conf > $PGDATA/postgresql.conf
echo "host replication $POSTGRES_USER 0.0.0.0/0 trust" >> $PGDATA/pg_hba.conf
echo "host  all  all  127.0.0.1/32  trust" >> $PGDATA/pg_hba.conf