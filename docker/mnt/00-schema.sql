-- Strip everyone on rights to the public schema except for the user postgres
REVOKE ALL ON schema public FROM public;
GRANT ALL ON schema public TO postgres;


-- Provide read only access to the schema and its current content
CREATE ROLE public_readonly;
GRANT CONNECT ON DATABASE postgres TO public_readonly;
GRANT USAGE ON SCHEMA public TO public_readonly;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO public_readonly;

-- Provide read only access to future tables in the schema
ALTER DEFAULT PRIVILEGES IN SCHEMA public
GRANT SELECT ON TABLES TO public_readonly;