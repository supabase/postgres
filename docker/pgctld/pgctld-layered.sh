#!/bin/sh
exec /usr/local/bin/pgctld-bin \
	--postgres-config-template /etc/pgctld-custom/postgresql.conf.tmpl \
	--pg-initdb-sql-dirs supabase_admin:/etc/pgctld-custom/pre-init \
	--pg-initdb-sql-dirs postgres:/docker-entrypoint-initdb.d/init-scripts \
	--pg-initdb-sql-dirs supabase_admin:/docker-entrypoint-initdb.d/migrations \
	"$@"
