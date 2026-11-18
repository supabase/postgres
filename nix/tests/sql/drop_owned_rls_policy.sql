-- Fixes CVE-2026-116311.
--
-- What changed: `DROP OWNED BY some_role` could remove the role from RLS policies on tables the caller doesn't own.
-- A role could use this to escape a restrictive policy.
-- Postgres now leaves those policies alone and issues a WARNING.
--
-- Who notices: clean-up scripts that run `DROP OWNED BY some_role` as a role that doesn't own every affected table.
-- The policies stay, so a later `DROP ROLE some_role` can fail on the remaining dependency.
-- To fix: run the clean-up as the table owner (on Supabase, usually `postgres`), or remove the role from those policies first.
--
-- Upstream commits: 1f2dd21c1 (PG 15.20), 21c732aad (PG 17.12).

BEGIN;

CREATE ROLE regress_dob_role NOLOGIN;
CREATE TABLE dob_tbl (c int);
ALTER TABLE dob_tbl ENABLE ROW LEVEL SECURITY;
CREATE POLICY dob_restrict ON dob_tbl AS RESTRICTIVE TO regress_dob_role USING (c > 0);

SET ROLE regress_dob_role;
DROP OWNED BY regress_dob_role; -- should warn
RESET ROLE;

-- Policy must still apply to regress_dob_role.
SELECT polname, polroles::regrole[] FROM pg_policy WHERE polrelid = 'dob_tbl'::regclass;

ROLLBACK;
