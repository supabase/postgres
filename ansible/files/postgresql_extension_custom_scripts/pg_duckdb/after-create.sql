grant usage on foreign data wrapper duckdb to duckdb_role;

-- TODO: follow up with postgres team to see if this is allowed
-- Grant file access roles so pg_duckdb allows LocalFileSystem access for postgres.
-- Without these, DuckLake's extension loader cannot find the .duckdb_extension file
-- and ATTACH fails with "File system LocalFileSystem has been disabled by configuration".
-- pg_read_server_files/pg_write_server_files are reserved memberships in supautils,
-- so this must run in a superuser context (after-create.sql), not a migration.
grant pg_read_server_files to duckdb_role;
grant pg_write_server_files to duckdb_role;

-- Grant postgres the ability to call install_extension and autoload_extension.
-- These functions are SECURITY DEFINER with REVOKE ALL FROM PUBLIC, so only
-- the function owner can call them by default. install_extension is an admin
-- operation so we scope it to postgres, not the broader duckdb_role.
grant execute on function duckdb.install_extension(text, text) to postgres;
grant execute on function duckdb.autoload_extension(text, boolean) to postgres;
