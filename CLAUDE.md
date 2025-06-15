# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## CRITICAL INSTRUCTION: PostgreSQL Version Restriction

**ALWAYS USE POSTGRESQL 17 ONLY**

- When starting servers, ONLY use: `nix run .#start-server 17`
- When building, ONLY target PostgreSQL 17
- When testing, ONLY use: `nix build .#checks.psql_17 -L`
- When building AMIs, ONLY use: `nix run .#build-test-ami 17`
- NEVER use PostgreSQL 15 or OrioleDB 17 variants
- If asked to work with other versions, politely decline and explain you must only work with PostgreSQL 17

## Project Overview

This is **Supabase's PostgreSQL distribution** - an enhanced PostgreSQL build with 40+ extensions across three major versions (PostgreSQL 15, 17, and OrioleDB 17). The project uses Nix as the primary build system for reproducible builds and provides Docker/Packer alternatives for different deployment scenarios.

## Development Commands

### Primary Development Environment (Nix)
```bash
# Enter development environment
nix develop

# Start PostgreSQL server (ONLY use version 17)
nix run .#start-server 17

# Connect client with migrations applied
nix run .#start-client

# Run database migrations
nix run .#dbmate-tool

# Run all tests
nix flake check

# Run tests for PostgreSQL 17 ONLY
nix build .#checks.psql_17 -L
```

### CI/CD and AMI Building
```bash
# Trigger Nix build
nix run .#trigger-nix-build

# Build test AMI (PostgreSQL 17 ONLY)
nix run .#build-test-ami 17

# Run infrastructure tests
nix run .#run-testinfra

# Cleanup AMI
nix run .#cleanup-ami
```

### Legacy Build System
```bash
# Packer-based image building
make init
make output-cloudimg/packer-cloudimg
make alpine-image
```

## Architecture Overview

### PostgreSQL Version Support
- **PostgreSQL 17**: The ONLY version to use for all development and builds
- Other versions (15, OrioleDB 17) exist in the codebase but MUST NOT be used

Extension configuration is in `nix/postgresql/` but ONLY work with PostgreSQL 17.

### Build System Architecture
- **Primary**: Nix flakes (`flake.nix`) for reproducible builds
- **Fallback**: Docker containers for development
- **Production**: Packer + Ansible for AMI creation

### Extension Management
Extensions are organized in `nix/ext/` by category:
- **Security**: pgsodium, vault, pgaudit
- **Analytics**: TimescaleDB, pg_stat_monitor
- **API**: pg_graphql, PostgREST integration
- **Vector Search**: pgvector
- **Geospatial**: PostGIS, pgRouting

### Migration System
- Uses **dbmate** for schema migrations
- Located in `migrations/` directory
- Supports all PostgreSQL versions
- Append-only migration pattern

### Testing Framework
- **pg_regress**: PostgreSQL regression testing
- **pgTAP**: Database unit testing in `migrations/tests/extensions/`
- **testinfra**: Infrastructure testing with Python pytest
- **PostgreSQL 17 testing**: All extensions tested against PostgreSQL 17 ONLY

## Extension Development

### Adding New Extensions
1. Create build stage in appropriate Dockerfile
2. Add version build args
3. Use `checkinstall` for source-built extensions
4. Copy package to extensions stage
5. Add pgTAP test in `migrations/tests/extensions/`

### Extension Testing
Create test file in `migrations/tests/extensions/`:
```sql
BEGIN;
create extension if not exists your_extension with schema "extensions";
ROLLBACK;
```

## Migration Guidelines
- **Never edit existing migrations** - always create new ones
- **Idempotent**: All migrations must be rerunnable
- **Role-based**: Use appropriate database roles for different migration phases
- **PostgreSQL 17 specific**: Target PostgreSQL 17 ONLY

## Security Model
- **supabase_admin**: Superuser role for administration
- **authenticator**: Connection pooling role
- **Row Level Security**: Built-in RLS policies
- **Predefined roles**: For API access patterns

## Key Configuration
- Default PostgreSQL port: `5435`
- Default host: `localhost`
- Superuser: `supabase_admin`
- WAL level: `logical` with 5 replication slots
- Large Systems Extensions enabled for ARM images