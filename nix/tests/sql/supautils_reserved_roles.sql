-- verify non-superuser postgres role cannot drop supabase_privileged_role
BEGIN;

-- Switch to the postgres role (non-superuser) to test supautils behavior
SET ROLE postgres;

-- SAVEPOINT is needed to recover from the expected error and continue the transaction
SAVEPOINT before_drop;
DROP ROLE supabase_privileged_role;
ROLLBACK TO SAVEPOINT before_drop;

RESET ROLE;

SELECT rolname FROM pg_roles WHERE rolname = 'supabase_privileged_role';

ROLLBACK;

-- verify non-superuser postgres role cannot claim the reserved multigres_probe
-- name. The role only exists on Multigres images, so CREATE must be refused
-- by name before the role exists anywhere else.
BEGIN;

SET ROLE postgres;

SAVEPOINT before_create;
CREATE ROLE multigres_probe;
ROLLBACK TO SAVEPOINT before_create;

RESET ROLE;

SELECT count(*) FROM pg_roles WHERE rolname = 'multigres_probe';

ROLLBACK;
