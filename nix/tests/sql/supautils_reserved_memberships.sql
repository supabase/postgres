set role postgres;

grant pg_read_server_files to postgres;
grant pg_write_server_files to postgres;
grant pg_execute_server_program to postgres;
grant supabase_admin to postgres;
grant supabase_auth_admin to postgres;
grant supabase_storage_admin to postgres;
grant supabase_read_only_user to postgres;
grant supabase_realtime_admin to postgres;
grant supabase_replication_admin to postgres;
grant supabase_etl_admin to postgres;
grant dashboard_user to postgres;
grant pgbouncer to postgres;
grant authenticator to postgres;
grant pg_write_all_data to postgres;

reset role;
