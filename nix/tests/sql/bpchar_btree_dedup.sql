-- What changed: btree deduplication isn't safe for bpchar, because bpchar equality ignores trailing spaces.
-- In rare cases index-only scans returned wrong results.
-- Postgres no longer deduplicates bpchar_ops indexes.
-- New indexes report allequalimage = false, which this test checks.
--
-- Who notices: anyone with a btree index on a `bpchar` or `char(n)` column, including primary keys and unique constraints.
-- Upstream recommends a REINDEX after the upgrade.
-- Until then, amcheck's bt_index_check() reports these indexes as corrupt ("metapage incorrectly indicates that deduplication is safe").
-- Expect support tickets about it.
-- This query lists the indexes to rebuild:
--
--   SELECT DISTINCT i.indexrelid::regclass FROM pg_index i
--   JOIN pg_class c ON c.oid = i.indexrelid
--   JOIN pg_am am ON am.oid = c.relam AND am.amname = 'btree'
--   JOIN pg_attribute a ON a.attrelid = i.indrelid AND a.attnum = ANY (i.indkey)
--   WHERE a.atttypid = 'bpchar'::regtype;
--
-- Upstream commits: de0d4f0b1 (PG 15.20), 74f26a193 (PG 17.12).

BEGIN;

CREATE TABLE bpchar_dedup (b bpchar, c char(10), t text) USING heap;
CREATE INDEX bpchar_dedup_b ON bpchar_dedup (b);
CREATE INDEX bpchar_dedup_c ON bpchar_dedup (c);
CREATE INDEX bpchar_dedup_t ON bpchar_dedup (t);

-- bpchar and char(n) report false after the fix.
-- text still reports true.
SELECT 'b' AS col, allequalimage FROM bt_metap('bpchar_dedup_b')
UNION ALL SELECT 'c', allequalimage FROM bt_metap('bpchar_dedup_c')
UNION ALL SELECT 't', allequalimage FROM bt_metap('bpchar_dedup_t');

ROLLBACK;
