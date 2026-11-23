-- Fixes CVE-2026-6460.
--
-- What changed: after a column type change, stored expressions could still read the table's row type in its old layout.
-- That could crash the backend or expose memory.
-- Postgres now refuses ALTER COLUMN TYPE when certain stored code uses the row type.
-- It also adds the composite_type_mismatch setting.
--
-- Who notices: migrations such as `ALTER TABLE profiles ALTER COLUMN x TYPE ...`.
-- They now fail with "cannot alter table ... because function ... uses its row type" if the row type appears in any of these:
--   - a BEGIN ATOMIC function body
--   - a default for a function argument or a column
--   - an index expression on another table
-- To fix: drop the dependent object, run the ALTER, then recreate the object.
-- Functions that only take or return the row type are fine, for example `RETURNS SETOF profiles` for a PostgREST RPC.
--
-- Upstream commits: 22762f03a and others (PG 15.20), bfcb6625e and others (PG 17.12).

BEGIN;

-- The new GUC exists.
SELECT count(*) AS has_guc FROM pg_settings WHERE name = 'composite_type_mismatch';

CREATE TABLE act_tbl (a bytea);
CREATE FUNCTION act_func() RETURNS act_tbl
  IMMUTABLE LANGUAGE sql BEGIN ATOMIC SELECT '(\\x4649584d45)'::act_tbl; END;

-- Must now be rejected.
SAVEPOINT s;
ALTER TABLE act_tbl ALTER COLUMN a TYPE text;
ROLLBACK TO SAVEPOINT s;

ROLLBACK;
