# Spock Migration Steps

## Migration: Standard Supabase-Postgres → Spock-Enabled

### 1. Build & Deploy Spock Image
- [ ] Build `~/supabase-postgres-spock` image
- [ ] Push to registry / deploy to nodes

### 2. Configure PostgreSQL for Replication
- [ ] Set `wal_level = logical`
- [ ] Set `max_replication_slots = 10` (or higher)
- [ ] Set `max_wal_senders = 10` (or higher)
- [ ] Set `shared_preload_libraries = 'spock'`
- [ ] Restart PostgreSQL

### 3. Create Spock Extension (Both Nodes)
```sql
CREATE EXTENSION IF NOT EXISTS spock;
```

### 4. Create Spock Nodes
```sql
-- On PRIMARY:
SELECT spock.node_create('primary_node', 'host=<primary_host> dbname=postgres user=postgres password=<pass>');

-- On STANDBY:
SELECT spock.node_create('standby_node', 'host=<standby_host> dbname=postgres user=postgres password=<pass>');
```

### 5. Create Replication Sets
```sql
-- Both nodes:
SELECT spock.repset_create('default');
SELECT spock.repset_create('ddl_sql');
```

### 6. Create Subscriptions (Bi-directional)
```sql
-- On STANDBY (subscribe to PRIMARY):
SELECT spock.sub_create('sub_from_primary', 'host=<primary_host> ...', ARRAY['default','ddl_sql'], true);

-- On PRIMARY (subscribe to STANDBY):
SELECT spock.sub_create('sub_from_standby', 'host=<standby_host> ...', ARRAY['default','ddl_sql'], true);
```

### 7. Configure Sequences for Bi-directional (Per Table)
```sql
-- PRIMARY (odd IDs: 1,3,5...):
ALTER SEQUENCE <table>_<col>_seq INCREMENT BY 2 RESTART WITH 1;

-- STANDBY (even IDs: 2,4,6...):
ALTER SEQUENCE <table>_<col>_seq INCREMENT BY 2 RESTART WITH 2;
```

### 8. Add Existing Tables to Replication Sets
```sql
-- Both nodes, for each table:
SELECT spock.repset_add_table('default', '<schema>.<table>', true);
```

### 9. Verify Replication
```sql
-- Check subscription status:
SELECT * FROM spock.sub_show_status();

-- Check sync status:
SELECT * FROM spock.local_sync_status;

-- Check replication slots:
SELECT slot_name, active, restart_lsn FROM pg_replication_slots WHERE slot_name LIKE 'spk%';
```

---

## Completed (Dev) - 2026-01-25

- [x] Steps 1-6: Spock configured on dev PRIMARY and STANDBY
- [x] Step 7: Sequence fix applied to replicated tables:
  - `public.ddl_test_v2_id_seq` - PRIMARY: RESTART 3, STANDBY: RESTART 4
  - `public.spock_test_id_seq` - PRIMARY: RESTART 6000003, STANDBY: RESTART 6000002
  - `public.spock_cli_test_id_seq` - already fixed
- [x] Step 8: Tables already in replication sets (ddl_test_v2, spock_test, spock_cli_test)
- [x] Step 9: Verified bi-directional replication
  - Insert on PRIMARY → ID 6000003 (odd) → replicated to STANDBY ✅
  - Insert on STANDBY → ID 6000002 (even) → replicated to PRIMARY ✅

## CLI Integration Completed - 2026-01-26

- [x] CLI `supabase db push` tested with Spock mode
- [x] CLI automatically:
  - Wraps DDL in `spock.replicate_ddl()` for table creation
  - Detects SERIAL/BIGSERIAL columns and configures sequences
  - Sets INCREMENT BY 2 with different START values per node
  - Adds tables to replication sets on BOTH nodes
- [x] CLI `supabase migration repair` for safe rollback (does NOT use destructive `migration down`)
- [x] Rollback workflow: `repair` → `repset_remove_table` → `replicate_ddl(DROP TABLE)`

## Production Readiness Testing Completed - 2026-01-26

### Tested & Verified
- [x] INSERT/UPDATE/DELETE bi-directional replication
- [x] DDL: CREATE TABLE, ALTER TABLE ADD/DROP COLUMN, CREATE INDEX, DROP TABLE
- [x] Data types: UUID, SERIAL, TEXT, JSONB, ARRAY, BYTEA
- [x] Foreign key relationships (with timing awareness)
- [x] Multi-table transactions
- [x] Transaction ROLLBACK (correctly not replicated)
- [x] NULL values
- [x] Large TEXT (10KB+)
- [x] Load testing (40 concurrent inserts)
- [x] Conflict resolution (apply_remote)
- [x] Monitoring queries documented and tested

### Tables in Replication (Dev)
- public.profiles (UUID PK)
- public.chats (UUID PK)
- public.spock_test
- public.spock_cli_test
- public.ddl_test_v2
- public.scorecard_test
- public.scorecard_test2
- public.ddl_alter_test
- public.fk_parent_test
- public.fk_child_test

### Destructive Tests Completed (on test tables) - 2026-01-26
- [x] DELETE replication (spock_test) - row deleted on both nodes
- [x] TRUNCATE replication (scorecard_test) - table emptied on both nodes
- [x] DELETE with FK CASCADE (fk_parent/child_test) - parent + cascaded child replicated

### Outage Simulation Tests Completed - 2026-01-26
- [x] STANDBY node outage - PRIMARY continued, WAL accumulated (6312 bytes), auto-recovered
- [x] PRIMARY node outage - STANDBY continued, WAL accumulated (816 bytes), auto-recovered
- [x] WAL accumulation during outage - observed and recovered on both tests
- [x] Replication auto-resume - slots reactivated automatically after node restart

### ⚠️ Advanced Recovery Tests - CRITICAL ISSUES FOUND

| Test | Result | Action Required |
|------|--------|-----------------|
| Split-brain | ⚠️ DIVERGENCE | `apply_remote` causes stable divergence - manual fix required |
| `sub_resync_table()` | ⚠️ DANGEROUS | Can cause data loss - avoid in production |

**PRODUCTION RECOMMENDATIONS:**
1. Consider `last_update_wins` instead of `apply_remote` for conflict resolution
2. NEVER use `sub_resync_table()` - use manual COPY instead
3. Recovery from stuck sync requires superuser access (docker exec)

See `SPOCK_SCORECARD.md` for detailed test results and monitoring queries.

## TODO (Production)

### Infrastructure Setup
- [ ] Build Spock-enabled PostgreSQL image
- [ ] Deploy to both PRIMARY and STANDBY nodes
- [ ] Configure PostgreSQL (`wal_level=logical`, `max_replication_slots`, etc.)
- [ ] Create `spock` extension on both nodes
- [ ] Create Spock nodes with proper connection strings
- [ ] Create replication sets (`default`, `ddl_sql`)
- [ ] Create bi-directional subscriptions

### CLI Configuration
- [ ] Update `supabase/config.toml` on PRIMARY with:
```toml
[db.spock]
enabled = true
remote_dsn = "postgresql://postgres:<password>@<standby_host>:<port>/postgres?sslmode=<mode>"
replication_sets = ["default", "ddl_sql"]
default_repset = "default"
auto_add_tables = true
node_offset = 1  # PRIMARY = odd IDs
max_wait_attempts = 30
base_wait_delay_ms = 100
verbose = true
```

- [ ] Update `supabase/config.toml` on STANDBY with:
```toml
[db.spock]
enabled = true
remote_dsn = "postgresql://postgres:<password>@<primary_host>:<port>/postgres?sslmode=<mode>"
replication_sets = ["default", "ddl_sql"]
default_repset = "default"
auto_add_tables = true
node_offset = 2  # STANDBY = even IDs
max_wait_attempts = 30
base_wait_delay_ms = 100
verbose = true
```

### Add Existing App Tables to Replication
For each table (run on BOTH nodes):
```sql
-- Skip tables with SERIAL PKs that need sequence fixing first
SELECT spock.repset_add_table('default', 'public.<table_name>', false);
```

For tables with SERIAL/BIGSERIAL PKs:
```sql
-- PRIMARY:
ALTER SEQUENCE public.<table>_<column>_seq INCREMENT BY 2 RESTART WITH <next_odd>;
-- STANDBY:
ALTER SEQUENCE public.<table>_<column>_seq INCREMENT BY 2 RESTART WITH <next_even>;
```

### Tables to Add (Brainwires App)
| Table | PK Type | Sequence Config Needed |
|-------|---------|------------------------|
| profiles | UUID | No |
| chats | UUID | No |
| chat_messages | UUID | No |
| files | UUID | No |
| workspaces | UUID | No |
| usage | UUID | No |
| models | TEXT | No |
| places | BIGSERIAL | YES - needs INCREMENT BY 2 |
| (add all other tables) | | |

### Monitoring Setup
- [ ] Create monitoring dashboard with queries from SPOCK_SCORECARD.md
- [ ] Configure alerts:
  - Replication lag > 1MB for > 30 seconds
  - Subscription disabled (sub_enabled = false)
  - Slot inactive or lag > 100MB
  - Tables with sync_status != 'r'

### Verification
- [ ] Test INSERT on PRIMARY → verify on STANDBY
- [ ] Test INSERT on STANDBY → verify on PRIMARY
- [ ] Test UPDATE bi-directional
- [ ] Run CLI `supabase db push` with test migration
- [ ] Verify CLI rollback workflow works

### Documentation
- [ ] Document network interruption recovery procedure
- [ ] Document node failure recovery procedure
- [ ] Document how to add new tables to replication
