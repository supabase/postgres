-- What changed: jsonpath searches with `@@` and `@?` on a jsonb_ops GIN index missed matching rows in these cases:
--   - a top-level scalar, for example `strict $ == "a scalar"`
--   - a method on a literal, for example `"25".double()`
--   - an AND inside a NOT
-- The test checks that index scans find the same rows as a sequential scan.
--
-- Who notices: these queries may return more rows after the upgrade (the correct ones).
-- Before, the result depended on whether the planner chose the index.
-- Existing indexes don't need a REINDEX.
--
-- Upstream commits: 3b2a60481 + 04a8915fa (PG 15.20), 19656b77d + 65f1b71c3 (PG 17.12).

BEGIN;

CREATE TABLE jgin (j jsonb) USING heap;
INSERT INTO jgin VALUES
  ('"a scalar"'),
  ('{"age": 25}'),
  ('{"age": 25.0}'),
  ('{"bad": false, "coauthors": 98}'),
  ('{"bad": true, "coauthors": 98}'),
  ('{"bad": false, "coauthors": 1}'),
  ('{}');
CREATE INDEX jgin_idx ON jgin USING gin (j jsonb_ops);

-- Ground truth (seqscan).
SET LOCAL enable_bitmapscan = off;
SELECT count(*) FROM jgin WHERE j @@ 'strict $ == "a scalar"'::jsonpath;
SELECT count(*) FROM jgin WHERE j @@ '$.age == "25".double()'::jsonpath;
SELECT count(*) FROM jgin WHERE j @@ '!(!($.bad == false) && $.coauthors == 98)'::jsonpath;

-- Through the GIN index: must match.
SET LOCAL enable_bitmapscan = on;
SET LOCAL enable_seqscan = off;
SELECT count(*) FROM jgin WHERE j @@ 'strict $ == "a scalar"'::jsonpath;
SELECT count(*) FROM jgin WHERE j @@ '$.age == "25".double()'::jsonpath;
SELECT count(*) FROM jgin WHERE j @@ '!(!($.bad == false) && $.coauthors == 98)'::jsonpath;

ROLLBACK;
