
-- Sanity test object existence in storage schema
--
-- Storage tables and functions (storage.buckets, storage.objects, ...) are
-- created by the Storage service's own migrations, not by this repo (#1911).
-- We only create the schema and the role Storage connects as.

select has_schema('storage'::name);
select has_role('supabase_storage_admin'::name);

select todo('This test should probably fail.'); select schema_privs_are('storage', 'anon', ARRAY['USAGE']);

