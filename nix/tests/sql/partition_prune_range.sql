-- What changed: RANGE partition pruning could skip partitions that held matching rows, so queries silently returned too few rows.
-- Two cases:
--   - a multi-column partition key, with filters on only the leading columns
--   - a DEFAULT partition next to a partition bound that uses MINVALUE or MAXVALUE
-- The test checks that counts match those with enable_partition_pruning off.
--
-- Who notices: projects with tables like these, for example partitioned by (tenant_id, created_at).
-- Affected queries may return more rows after the upgrade (the correct ones).
-- All rows sit in the right partitions, so no data needs fixing.
--
-- Upstream commits: 1a501b6e2 + 9b8c0f238 (PG 15.20), 2d8494e24 + d21d4f1ca (PG 17.12).

BEGIN;

-- Multi-column RANGE, qual on the leading column only.
CREATE TABLE ppr_mc (a int, b int) PARTITION BY RANGE (a, b);
CREATE TABLE ppr_mc1 PARTITION OF ppr_mc FOR VALUES FROM (1, 4) TO (1, 7);
CREATE TABLE ppr_mc2 PARTITION OF ppr_mc FOR VALUES FROM (1, 7) TO (3, 8);
CREATE TABLE ppr_mc3 PARTITION OF ppr_mc FOR VALUES FROM (4, 8) TO (6, 9);
CREATE TABLE ppr_mc_def PARTITION OF ppr_mc DEFAULT;
INSERT INTO ppr_mc VALUES (1, 5), (1, 8), (2, 0), (5, 8), (0, 0);

-- DEFAULT partition next to a MAXVALUE bound.
CREATE TABLE ppr_max (a int, b int) PARTITION BY RANGE (a, b);
CREATE TABLE ppr_max1 PARTITION OF ppr_max FOR VALUES FROM (13, 0) TO (19, MAXVALUE);
CREATE TABLE ppr_max_def PARTITION OF ppr_max DEFAULT;
INSERT INTO ppr_max VALUES (15, 1), (32, 0), (25, 3);

-- DEFAULT partition next to a MINVALUE bound.
CREATE TABLE ppr_min (a int, b int) PARTITION BY RANGE (a, b);
CREATE TABLE ppr_min1 PARTITION OF ppr_min FOR VALUES FROM (13, MINVALUE) TO (19, 5);
CREATE TABLE ppr_min_def PARTITION OF ppr_min DEFAULT;
INSERT INTO ppr_min VALUES (15, 1), (5, 0), (13, 3);

-- With pruning.
SELECT count(*) FROM ppr_mc WHERE a <= 1;            -- (1,5), (1,8), (0,0)
SELECT count(*) FROM ppr_max WHERE a = 32 AND b >= -7;  -- (32,0)
SELECT count(*) FROM ppr_max WHERE a >= 25 AND b >= 0;  -- (32,0), (25,3)
SELECT count(*) FROM ppr_min WHERE a = 5 AND b <= 7;    -- (5,0)

-- Without pruning: must match.
SET LOCAL enable_partition_pruning = off;
SELECT count(*) FROM ppr_mc WHERE a <= 1;
SELECT count(*) FROM ppr_max WHERE a = 32 AND b >= -7;
SELECT count(*) FROM ppr_max WHERE a >= 25 AND b >= 0;
SELECT count(*) FROM ppr_min WHERE a = 5 AND b <= 7;

ROLLBACK;
