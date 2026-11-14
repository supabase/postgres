-- Fixes CVE-2026-120154.
--
-- What changed: on a table with RLS, Postgres evaluated an upsert's ON CONFLICT ... WHERE clause before the RLS USING policies.
-- A function in that clause could read rows the caller isn't allowed to see.
-- Postgres now checks the policies first, so nothing leaks.
--
-- Who notices: normal upserts behave the same.
-- The fix closes a way to read other users' rows on RLS-protected tables.
-- In this test, the function prints the row it sees; that NOTICE must no longer appear.
--
-- Upstream commits: 48be6f9e8 (PG 15.20), 9c677791d (PG 17.12).

BEGIN;

-- Supabase's postgres role bypasses RLS, so use a separate role.
CREATE ROLE regress_rls_upsert_user NOLOGIN NOBYPASSRLS;

CREATE TABLE rls_upsert_doc (id int PRIMARY KEY, owner name, body text);
INSERT INTO rls_upsert_doc VALUES (1, 'someone_else', 'secret');
ALTER TABLE rls_upsert_doc ENABLE ROW LEVEL SECURITY;
CREATE POLICY p_all ON rls_upsert_doc USING (owner = current_user);
GRANT SELECT, INSERT, UPDATE ON rls_upsert_doc TO regress_rls_upsert_user;

CREATE FUNCTION rls_upsert_leak(text) RETURNS boolean
  LANGUAGE plpgsql COST 0.0000001
  AS $$ BEGIN RAISE NOTICE 'leaked => %', $1; RETURN true; END $$;

SET ROLE regress_rls_upsert_user;

-- Must fail without a "leaked => secret" NOTICE.
SAVEPOINT s;
INSERT INTO rls_upsert_doc VALUES (1, 'regress_rls_upsert_user', 'x')
  ON CONFLICT (id) DO UPDATE SET body = EXCLUDED.body
  WHERE rls_upsert_leak(rls_upsert_doc.body);
ROLLBACK TO SAVEPOINT s;

RESET ROLE;

ROLLBACK;
