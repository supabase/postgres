# Spock Bi-Directional Replication - Production Issues

## Critical Issues to Fix Before Production

### 1. Sequence Conflicts (CRITICAL)
**Problem:** Default SERIAL/BIGSERIAL sequences generate the same IDs on both nodes, causing primary key conflicts.

**Solution:** Configure sequences with different starting points and increments:
```sql
-- PRIMARY: odd IDs (1, 3, 5, ...)
ALTER SEQUENCE <table>_id_seq INCREMENT BY 2 RESTART WITH 1;

-- STANDBY: even IDs (2, 4, 6, ...)
ALTER SEQUENCE <table>_id_seq INCREMENT BY 2 RESTART WITH 2;
```

**Status:** Needs to be done for EVERY table with SERIAL/BIGSERIAL columns.

---

### 2. Initial Sync Failures
**Problem:** When a new table is added to a replication set, the initial sync can fail and get stuck in status `i` (init), causing the apply worker to crash repeatedly.

**Symptoms:**
- Apply worker connects then immediately exits with error
- Sync status shows `i` instead of `r`
- Logs show "sync worker exiting with error" with no details

**Solution:**
1. Check sync status: `SELECT * FROM spock.local_sync_status;`
2. If stuck at `i`, manually update: `UPDATE spock.local_sync_status SET sync_status = 'r' WHERE sync_relname = 'table_name';`
3. If that doesn't work, advance the replication slot: `SELECT pg_replication_slot_advance('slot_name', pg_current_wal_lsn());`

---

### 3. Replication Slot LSN Mismatch
**Problem:** The standby can get stuck trying to replay from an old LSN that contains problematic transactions.

**Symptoms:**
- Subscription shows "down"
- Apply worker connects then immediately crashes
- PRIMARY logs show "unexpected EOF on standby connection"

**Solution:**
```sql
-- On PRIMARY, advance the slot to current position:
SELECT pg_replication_slot_advance('spk_postgres_primary_dev_sub_from_primary', pg_current_wal_lsn());
-- Then re-enable subscription on STANDBY
```

---

### 4. SSL/TLS Configuration
**Problem:** Connection strings need `sslmode=disable` when using Cloudflare tunnels (or other non-TLS tunnels).

**Solution:** Ensure node_interface DSN includes `sslmode=disable`:
```sql
UPDATE spock.node_interface
SET if_dsn = 'host=... sslmode=disable'
WHERE if_name = 'remote_node';
```

---

### 5. Conflict Resolution - CRITICAL ISSUE FOUND

**Problem:** Default `apply_remote` conflict resolution causes **STABLE DIVERGENCE** in split-brain scenarios.

**What happens:** When both nodes update the same row during a partition:
- Each node accepts the remote version
- Nodes end up with DIFFERENT values (no convergence)
- Manual intervention required to fix

**Current Setting:** `SHOW spock.conflict_resolution;` → `last_update_wins` ✅ (Applied 2026-01-26)

**VERIFIED:** Split-brain test with `last_update_wins` showed proper convergence - both nodes got the value with the later timestamp.

### 6. sub_resync_table() is DANGEROUS

**Problem:** `spock.sub_resync_table()` truncates the table then attempts to sync. If sync fails (gets stuck at 'i'), data is lost.

**STABILIZED** - Use the safe resync function instead:

```sql
-- Safe resync with auto-recovery (preserves data, handles stuck sync)
SELECT public.spock_safe_resync('sub_from_standby', 'table_name', 60);
```

**Configuration applied (both nodes):**
- `wal_sender_timeout = 5min`
- `wal_receiver_timeout = 5min`

### Manual Recovery (if needed):

### Helper Function (installed on both nodes)
```sql
-- Fix sync stuck at 'i' status (callable by postgres user)
SELECT public.spock_fix_stuck_sync('table_name');
```

### Manual Recovery Procedure:
```bash
# 1. Export from working node
psql $WORKING_NODE -c "COPY table TO '/tmp/backup.csv' CSV HEADER"
# 2. Import to broken node
psql $BROKEN_NODE -c "COPY table FROM '/tmp/backup.csv' CSV HEADER"
# 3. Delete stuck sync entry (requires superuser)
docker exec container psql -U supabase_admin -c "DELETE FROM spock.local_sync_status WHERE sync_relname = 'table'"
# 4. Re-add table with sync=false
psql $PROVIDER -c "SELECT spock.repset_add_table('default', 'schema.table', false)"
```

---

## CLI Integration Notes

The Supabase CLI fork at `~/supabase-cli` has been modified to support Spock:

### Configuration (`config.toml`)
```toml
[db.spock]
enabled = true
remote_dsn = "postgresql://user:pass@host:port/db?sslmode=disable"
replication_sets = ["default", "ddl_sql"]
default_repset = "default"
auto_add_tables = true
node_offset = 1              # 1=PRIMARY (odd IDs), 2=STANDBY (even IDs)
max_wait_attempts = 30       # Max attempts waiting for DDL replication
base_wait_delay_ms = 100     # Base delay between wait attempts
verbose = true               # Enable detailed logging
```

### What the CLI Does Automatically:
1. Wraps DDL statements with `spock.replicate_ddl()` using `$spock_ddl$` quoting
2. Adds new tables to replication set on PRIMARY
3. Waits for DDL replication to STANDBY
4. Adds new tables to replication set on STANDBY
5. **Detects SERIAL/BIGSERIAL columns** and configures sequences automatically
6. **Sets INCREMENT BY 2** with different START values based on `node_offset` config
7. Uses `synchronize_data=false` to avoid initial sync issues
8. Provides verbose logging when enabled

### What the CLI Does NOT Do:
1. Handle sync failures (manual intervention required)
2. Configure conflict resolution
3. Fix sequences on pre-existing tables (only new tables via migrations)

---

## Checklist Before Production

- [x] All sequences configured with node-specific increments (**CLI handles for new tables**)
- [ ] Both subscriptions showing status `replicating`
- [ ] All tables in sync status `r` (ready)
- [ ] `sslmode=disable` in node_interface DSN (if using tunnels)
- [x] Test bi-directional INSERT/UPDATE/DELETE (**Verified 2026-01-26**)
- [x] Verify no ID conflicts after inserts on both nodes (**Verified with 40 concurrent inserts**)
- [ ] Document conflict resolution strategy (default: `apply_remote`)
- [ ] Set up monitoring for subscription status
- [ ] Set up monitoring for replication lag

### Additional Verified Tests (2026-01-26)
- [x] DDL replication: CREATE TABLE, ALTER TABLE, CREATE INDEX, DROP TABLE
- [x] Data types: UUID, SERIAL, TEXT, JSONB, ARRAY, BYTEA
- [x] Foreign key relationships (timing awareness required)
- [x] Multi-table transactions
- [x] Transaction ROLLBACK (correctly NOT replicated)
- [x] NULL values
- [x] Large TEXT (10KB+)
- [x] Load testing (40 concurrent operations, no conflicts)
- [x] **DELETE replication** (tested on test tables)
- [x] **TRUNCATE replication** (tested on test tables)
- [x] **DELETE with FK CASCADE** (parent + cascaded child replicated)
- [x] **Node outage recovery** - both PRIMARY and STANDBY outages tested
- [x] **WAL accumulation** - observed during outages, auto-recovered after restart
- [x] **Replication auto-resume** - slots reactivated automatically

---

## Quick Health Check Commands

```bash
# Check subscription status
SELECT * FROM spock.sub_show_status();

# Check sync status
SELECT * FROM spock.local_sync_status;

# Check replication slots
SELECT slot_name, active, restart_lsn FROM pg_replication_slots WHERE slot_name LIKE 'spk%';

# Check node interface config
SELECT if_name, if_dsn FROM spock.node_interface;
```
