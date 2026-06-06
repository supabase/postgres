# Sample isolation spec -- proves the pg_isolation_regress harness runs in CI.
# This is not a regression test for any particular fix; it just exercises the
# stock PostgreSQL isolation tester so real concurrency specs (e.g. MERGE
# serialization, postgres_fdw EvalPlanQual) can be dropped in alongside it.
#
# Scenario: session s2 reads a row under READ COMMITTED before and after a
# concurrent UPDATE+COMMIT by session s1 -- the second read observes the
# committed change. No step blocks.

setup
{
  CREATE TABLE iso_sample (id int PRIMARY KEY, val int);
  INSERT INTO iso_sample VALUES (1, 100);
}

teardown
{
  DROP TABLE iso_sample;
}

session s1
step s1_begin  { BEGIN; }
step s1_update { UPDATE iso_sample SET val = val + 1 WHERE id = 1; }
step s1_commit { COMMIT; }

session s2
step s2_begin  { BEGIN ISOLATION LEVEL READ COMMITTED; }
step s2_read   { SELECT val FROM iso_sample WHERE id = 1; }
step s2_commit { COMMIT; }

permutation s1_begin s1_update s2_begin s2_read s1_commit s2_read s2_commit
