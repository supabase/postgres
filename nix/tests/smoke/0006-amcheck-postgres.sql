BEGIN;
SELECT plan(3);

-- Ensure we actually test CREATE EXTENSION under the postgres role.
DROP EXTENSION IF EXISTS amcheck;

SET ROLE postgres;

SELECT lives_ok(
  $$
    CREATE EXTENSION amcheck;
  $$,
  'postgres can enable amcheck'
);

SELECT lives_ok(
  $$
    CREATE TABLE amcheck_smoke_tbl(id int primary key);
    SELECT bt_index_check('amcheck_smoke_tbl_pkey'::regclass);
    DROP TABLE amcheck_smoke_tbl;
  $$,
  'postgres can use amcheck functions'
);

SELECT lives_ok(
  $$
    DROP EXTENSION amcheck;
  $$,
  'postgres can drop amcheck'
);

RESET ROLE;

SELECT * FROM finish();
ROLLBACK;
