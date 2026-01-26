# Spock Bi-Directional Replication System Setup

This document describes the complete infrastructure setup for the Spock bi-directional replication system between two PostgreSQL nodes.

---

## Table of Contents

1. [Infrastructure Overview](#1-infrastructure-overview)
2. [Docker Container Architecture](#2-docker-container-architecture)
3. [Spock Node Configuration](#3-spock-node-configuration)
4. [Network Configuration](#4-network-configuration)
5. [CLI Integration](#5-cli-integration)
6. [Key SQL Commands Reference](#6-key-sql-commands-reference)
7. [Troubleshooting Guide](#7-troubleshooting-guide)

---

## 1. Infrastructure Overview

### Topology

Two-node bi-directional (multi-master) replication topology using Spock 3.1.8 on PostgreSQL 15.

| Role | Hostname | Database Container | Port |
|------|----------|-------------------|------|
| **PRIMARY** | `beta.brainwires.net` | `supabase-dev-db` | 25432 |
| **STANDBY** | `brainwires.net` | `supabase-dev-db` | 25432 |

### Connectivity

Cross-machine connectivity is achieved via **Cloudflare Zero Trust tunnels**, providing secure connections without exposing database ports to the public internet.

### Replication Flow

```
PRIMARY (beta.brainwires.net)          STANDBY (brainwires.net)
┌──────────────────────────────┐      ┌──────────────────────────────┐
│  supabase-dev-db             │      │  supabase-dev-db             │
│  (PostgreSQL 15 + Spock)     │      │  (PostgreSQL 15 + Spock)     │
│                              │      │                              │
│  Node: primary_dev           │◄────►│  Node: standby_dev           │
│  Subscription: sub_from_     │      │  Subscription: sub_from_     │
│                standby       │      │                primary       │
└──────────────────────────────┘      └──────────────────────────────┘
         │                                      │
         │ Cloudflare Tunnel                    │ Cloudflare Tunnel
         ▼                                      ▼
   pg-standby-dev.brainwires.net         pg-primary-dev.brainwires.net
        :45432                                  :45432
```

---

## 2. Docker Container Architecture

### PRIMARY Node (beta.brainwires.net)

| Container | Purpose | Port |
|-----------|---------|------|
| `supabase-dev-db` | PostgreSQL 15 with Spock 3.1.8 extension | 25432 (exposed) |
| `cloudflared-pg-replication-dev` | Cloudflare tunnel connecting to standby | Tunnel to `pg-standby-dev.brainwires.net:45432` |
| `spock-tunnel-proxy` | Socat proxy exposing tunnel port to host network | 45432 (internal) |

### STANDBY Node (brainwires.net)

| Container | Purpose | Port |
|-----------|---------|------|
| `supabase-dev-db` | PostgreSQL 15 with Spock 3.1.8 extension | 25432 (exposed) |
| `cloudflared-pg-replication-dev` | Cloudflare tunnel connecting to primary | Tunnel to `pg-primary-dev.brainwires.net:45432` |

### Container Networking

The containers communicate through the Docker network `supabase-dev_default`. The cloudflared container provides access to the remote node through the Cloudflare tunnel, which appears as a local hostname within the Docker network.

---

## 3. Spock Node Configuration

### Node Names

| Machine | Spock Node Name |
|---------|-----------------|
| PRIMARY (beta.brainwires.net) | `primary_dev` |
| STANDBY (brainwires.net) | `standby_dev` |

### Replication Sets

| Replication Set | Purpose |
|-----------------|---------|
| `default` | Standard table replication (INSERT, UPDATE, DELETE, TRUNCATE) |
| `ddl_sql` | DDL command replication via `spock.replicate_ddl()` |
| `default_insert_only` | Tables without primary keys (INSERT only) |

### Subscriptions

| On Node | Subscription Name | Subscribes From |
|---------|-------------------|-----------------|
| PRIMARY (`primary_dev`) | `sub_from_standby` | `standby_dev` |
| STANDBY (`standby_dev`) | `sub_from_primary` | `primary_dev` |

### Replication User

- **Username:** `spock_replicator`
- **Required privileges:** Superuser or replication role
- **Purpose:** Dedicated user for replication connections

### PostgreSQL Configuration Requirements

```ini
# postgresql.conf settings required for Spock
wal_level = 'logical'
max_worker_processes = 10
max_replication_slots = 10
max_wal_senders = 10
shared_preload_libraries = 'spock'
track_commit_timestamp = on
```

---

## 4. Network Configuration

### Docker Network

- **Network name:** `supabase-dev_default`
- **Type:** Bridge network (created by Docker Compose)

### Internal Hostnames

Within the Docker network, the Cloudflare tunnel container is accessible at:
- `cloudflared-pg-replication-dev:45432`

### DSN Connection Strings

**Important:** `sslmode=disable` is required for tunnel connections since SSL is handled by the Cloudflare tunnel itself.

**From PRIMARY to STANDBY:**
```
host=cloudflared-pg-replication-dev port=45432 dbname=postgres user=spock_replicator sslmode=disable
```

**From STANDBY to PRIMARY:**
```
host=cloudflared-pg-replication-dev port=45432 dbname=postgres user=spock_replicator sslmode=disable
```

### Cloudflare Tunnel Hostnames

| Tunnel Hostname | Connects To |
|-----------------|-------------|
| `pg-standby-dev.brainwires.net:45432` | STANDBY PostgreSQL |
| `pg-primary-dev.brainwires.net:45432` | PRIMARY PostgreSQL |

---

## 5. CLI Integration

### Modified Supabase CLI

The Supabase CLI has been modified to support Spock replication. The modified CLI is located at:
```
~/supabase-cli
```

### Configuration (config.toml)

Spock replication is configured in the `[db.spock]` section of `config.toml`:

```toml
[db.spock]
# Enable Spock replication mode for migrations
enabled = true

# Connection string for the remote Spock node
remote_dsn = "env(SPOCK_REMOTE_DSN)"

# Replication sets to use for DDL replication
replication_sets = ["default", "ddl_sql"]

# Default replication set for adding new tables
default_repset = "default"

# Automatically add new tables to replication sets on both nodes
auto_add_tables = true

# Node offset for sequence IDs (1=PRIMARY/odd, 2=STANDBY/even)
# IMPORTANT: Use different values on each node to avoid ID conflicts
node_offset = 1

# Timeout configuration for waiting for DDL replication
max_wait_attempts = 30       # Max attempts before timing out
base_wait_delay_ms = 100     # Base delay between attempts (exponential backoff)

# Enable verbose logging for debugging
verbose = true
```

**Important:** The `node_offset` must be different on each node:
- **PRIMARY:** `node_offset = 1` (generates odd IDs: 1, 3, 5, ...)
- **STANDBY:** `node_offset = 2` (generates even IDs: 2, 4, 6, ...)

### Environment Variables

Set the remote DSN as an environment variable:
```bash
export SPOCK_REMOTE_DSN="host=cloudflared-pg-replication-dev port=45432 dbname=postgres user=spock_replicator sslmode=disable"
```

### Auto DDL Wrapping

When `[db.spock].enabled = true`, the CLI automatically:

1. **Wraps DDL statements** with `spock.replicate_ddl()` for replication:
   ```sql
   SELECT spock.replicate_ddl($spock_ddl$
     CREATE TABLE example (id serial PRIMARY KEY, name text);
   $spock_ddl$, ARRAY['default','ddl_sql']);
   ```

2. **Auto-adds new tables** to replication sets on both nodes when `auto_add_tables = true`:
   ```sql
   -- On PRIMARY (local)
   SELECT spock.repset_add_table('default', 'public.example', false);
   -- Waits for table to appear on STANDBY via DDL replication...
   -- On STANDBY (remote)
   SELECT spock.repset_add_table('default', 'public.example', false);
   ```

3. **Configures sequences** for SERIAL/BIGSERIAL columns to avoid ID conflicts:
   ```sql
   -- On PRIMARY (node_offset=1): odd IDs
   ALTER SEQUENCE public.example_id_seq INCREMENT BY 2 RESTART WITH 1;
   -- On STANDBY (node_offset=2): even IDs
   ALTER SEQUENCE public.example_id_seq INCREMENT BY 2 RESTART WITH 2;
   ```

### Migration Rollback

**IMPORTANT:** Never use `supabase migration down` with Spock - it attempts a full database reset.

Use this safe rollback workflow instead:
```bash
# 1. Mark migration as reverted (does NOT execute any SQL)
supabase migration repair 20260101000000 --status reverted

# 2. Remove table from replication on BOTH nodes
psql $PRIMARY -c "SELECT spock.repset_remove_table('default', 'public.table_name');"
psql $STANDBY -c "SELECT spock.repset_remove_table('default', 'public.table_name');"

# 3. Drop table via replicated DDL (replicates to both nodes)
psql $PRIMARY -c "SELECT spock.replicate_ddl(\$spock_ddl\$DROP TABLE IF EXISTS public.table_name;\$spock_ddl\$, ARRAY['default','ddl_sql']);"
```

---

## 6. Key SQL Commands Reference

### Node Management

```sql
-- Create a node (run on each machine)
SELECT spock.node_create(
    node_name := 'primary_dev',
    dsn := 'host=localhost port=5432 dbname=postgres'
);

-- Add an interface for remote connections
SELECT spock.node_add_interface(
    node_name := 'primary_dev',
    interface_name := 'primary_dev_tunnel',
    dsn := 'host=pg-primary-dev.brainwires.net port=45432 dbname=postgres sslmode=disable'
);

-- Drop a node
SELECT spock.node_drop('node_name', ifexists := true);
```

### Subscription Management

```sql
-- Create subscription (for bi-directional, run on both nodes)
SELECT spock.sub_create(
    subscription_name := 'sub_from_primary',
    provider_dsn := 'host=cloudflared-pg-replication-dev port=45432 dbname=postgres user=spock_replicator sslmode=disable',
    replication_sets := '{default,ddl_sql}',
    synchronize_data := false,
    forward_origins := '{}'  -- Empty array prevents infinite loops in bi-directional setup
);

-- Wait for subscription to sync
SELECT spock.sub_wait_for_sync('sub_from_primary');

-- Enable/disable subscription
SELECT spock.sub_enable('sub_from_primary', immediate := true);
SELECT spock.sub_disable('sub_from_primary', immediate := true);

-- Drop subscription
SELECT spock.sub_drop('sub_from_primary');

-- Change subscription interface
SELECT spock.sub_alter_interface('sub_from_primary', 'new_interface_name');
```

### Sync Status Checks

```sql
-- Show subscription status
SELECT * FROM spock.sub_show_status();
SELECT * FROM spock.sub_show_status('sub_from_primary');

-- Show table sync status
SELECT * FROM spock.sub_show_table('sub_from_primary', 'public.my_table');

-- Check local sync status (detailed)
SELECT * FROM spock.local_sync_status;

-- Check replication slots
SELECT slot_name, active, restart_lsn, confirmed_flush_lsn
FROM pg_replication_slots
WHERE slot_name LIKE '%spock%';

-- View replication lag
SELECT * FROM spock.lag_tracker;

-- Check channel statistics
SELECT * FROM spock.channel_summary_stats;
SELECT * FROM spock.channel_table_stats;
```

### Replication Set Management

```sql
-- Add table to replication set
SELECT spock.repset_add_table('default', 'public.my_table', synchronize_data := true);

-- Add all tables in schema
SELECT spock.repset_add_all_tables('default', ARRAY['public'], synchronize_data := false);

-- Remove table from replication set
SELECT spock.repset_remove_table('default', 'public.my_table');

-- View tables in replication sets
SELECT * FROM spock.tables;

-- Create custom replication set
SELECT spock.repset_create(
    set_name := 'my_repset',
    replicate_insert := true,
    replicate_update := true,
    replicate_delete := true,
    replicate_truncate := true
);
```

### DDL Replication

```sql
-- Replicate DDL to subscribers
SELECT spock.replicate_ddl(
    'CREATE TABLE public.new_table (id serial PRIMARY KEY, data text)',
    '{default,ddl_sql}'
);

-- Multiple DDL commands
SELECT spock.replicate_ddl(ARRAY[
    'ALTER TABLE public.my_table ADD COLUMN new_col text',
    'CREATE INDEX idx_new_col ON public.my_table(new_col)'
], '{ddl_sql}');
```

### Resync Operations

```sql
-- Resync a single table (WARNING: truncates table first!)
SELECT spock.sub_resync_table('sub_from_primary', 'public.my_table');

-- Resync all tables in subscription
SELECT spock.sub_alter_sync('sub_from_primary', truncate := false);

-- Wait for table sync
SELECT spock.table_wait_for_sync('sub_from_primary', 'public.my_table');

-- Wait for all slots to confirm LSN
SELECT spock.wait_slot_confirm_lsn(NULL, NULL);
```

### Sequence Management

```sql
-- Sync sequence state to subscribers
SELECT spock.sync_seq('public.my_sequence');

-- Add sequence to replication set
SELECT spock.repset_add_seq('default', 'public.my_sequence', synchronize_data := true);
```

---

## 7. Troubleshooting Guide

### Subscription Down Issues

**Symptoms:** Subscription shows as disabled or not replicating.

**Diagnosis:**
```sql
-- Check subscription status
SELECT * FROM spock.sub_show_status();

-- Check for errors in PostgreSQL logs
-- Look for "spock" or subscription name in logs
```

**Resolution:**
```sql
-- Re-enable subscription
SELECT spock.sub_enable('sub_from_primary', immediate := true);

-- If interface changed, update it
SELECT spock.sub_alter_interface('sub_from_primary', 'correct_interface');
```

### Sync Stuck at 'i' Status

**Symptoms:** Table sync status shows `i` (initializing) and doesn't progress.

**Diagnosis:**
```sql
-- Check sync status
SELECT * FROM spock.local_sync_status WHERE sync_status = 'i';

-- Check if initial copy is running
SELECT * FROM pg_stat_activity WHERE application_name LIKE '%spock%';
```

**Resolution:**
```sql
-- Force resync of stuck table
SELECT spock.sub_resync_table('sub_from_primary', 'public.stuck_table');

-- Or disable and re-enable subscription
SELECT spock.sub_disable('sub_from_primary', immediate := true);
SELECT spock.sub_enable('sub_from_primary', immediate := true);
```

### Replication Slot LSN Problems

**Symptoms:** Replication slot's `restart_lsn` is far behind, causing WAL accumulation.

**Diagnosis:**
```sql
-- Check slot lag
SELECT slot_name,
       pg_wal_lsn_diff(pg_current_wal_insert_lsn(), restart_lsn) AS lag_bytes,
       active
FROM pg_replication_slots;

-- Check if slot is active
SELECT * FROM pg_replication_slots WHERE active = false;
```

**Resolution:**
```sql
-- If subscriber is truly gone, drop the slot (CAUTION!)
SELECT pg_drop_replication_slot('slot_name');

-- Then recreate subscription on subscriber
```

### Sequence Conflict Resolution

**Symptoms:** Duplicate key errors on sequences when both nodes insert simultaneously.

**Prevention:**
Use different sequence ranges on each node:

```sql
-- On PRIMARY: Use odd numbers
ALTER SEQUENCE public.my_table_id_seq INCREMENT BY 2 RESTART WITH 1;

-- On STANDBY: Use even numbers
ALTER SEQUENCE public.my_table_id_seq INCREMENT BY 2 RESTART WITH 2;
```

**Alternative:** Use Snowflake sequences for guaranteed uniqueness:
```sql
-- Convert to snowflake sequence (requires snowflake extension)
SELECT spock.convert_sequence_to_snowflake('public.my_table_id_seq');
```

### Connection Refused to Tunnel

**Symptoms:** Subscription cannot connect, "connection refused" errors.

**Diagnosis:**
```bash
# Check if cloudflared container is running
docker ps | grep cloudflared

# Check tunnel connectivity from within Docker network
docker exec supabase-dev-db pg_isready -h cloudflared-pg-replication-dev -p 45432

# Check cloudflared logs
docker logs cloudflared-pg-replication-dev
```

**Resolution:**
1. Restart the cloudflared container
2. Verify Cloudflare tunnel configuration
3. Check if spock-tunnel-proxy (if used) is running

### Conflict Resolution Errors

**Symptoms:** Replication stops with conflict errors.

**Diagnosis:**
```sql
-- Check conflict resolution setting
SHOW spock.conflict_resolution;

-- Check logged conflicts
SELECT * FROM spock.resolutions ORDER BY log_time DESC LIMIT 10;
```

**Resolution:**
```sql
-- Set automatic conflict resolution
ALTER SYSTEM SET spock.conflict_resolution = 'last_update_wins';
SELECT pg_reload_conf();

-- Or handle manually by fixing conflicting row and resuming
SELECT spock.sub_enable('sub_from_primary', immediate := true);
```

### Viewing Detailed Replication Stats

```sql
-- Overall stats per subscription
SELECT * FROM spock.channel_summary_stats;

-- Per-table stats
SELECT * FROM spock.channel_table_stats;

-- Reset stats
SELECT spock.reset_channel_stats();
```

---

## Quick Reference Card

### Essential Status Checks
```sql
SELECT * FROM spock.sub_show_status();                    -- Subscription status
SELECT * FROM spock.local_sync_status;                    -- Sync status
SELECT * FROM pg_replication_slots;                       -- Replication slots
SELECT * FROM spock.lag_tracker;                          -- Replication lag
```

### Monitoring Queries (with Alert Thresholds)

```sql
-- Replication lag in bytes (ALERT if > 1MB for > 30 seconds)
SELECT client_addr, state,
       pg_wal_lsn_diff(sent_lsn, replay_lsn) AS lag_bytes
FROM pg_stat_replication;

-- Subscription health (ALERT if sub_enabled = false)
SELECT sub_name, sub_enabled, sub_slot_name
FROM spock.subscription;

-- Slot status (ALERT if active = false or lag > 100MB)
SELECT slot_name, active,
       pg_wal_lsn_diff(pg_current_wal_lsn(), restart_lsn) AS lag_bytes
FROM pg_replication_slots
WHERE slot_name LIKE 'spk%';

-- Tables not in sync (ALERT if sync_status != 'r')
SELECT sync_relname, sync_status
FROM spock.local_sync_status
WHERE sync_status != 'r';
```

### Common Operations
```sql
SELECT spock.sub_enable('sub_name', true);                -- Enable subscription
SELECT spock.sub_disable('sub_name', true);               -- Disable subscription
SELECT spock.repset_add_table('default', 'schema.table'); -- Add table
SELECT spock.replicate_ddl('DDL COMMAND', '{ddl_sql}');   -- Replicate DDL
```

### Emergency Recovery
```sql
-- Resync everything (use with caution)
SELECT spock.sub_alter_sync('sub_name', truncate := false);
SELECT spock.sub_wait_for_sync('sub_name');
```
