# Minimal PostgreSQL for Supabase CLI Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Create a minimal PostgreSQL + supautils package for darwin/arm64 that can be bundled with the Supabase CLI for local development without Docker.

**Architecture:** Build a new `psql_*_cli` package variant containing only PostgreSQL core + supautils extension, with systemd disabled and optimized for minimal size. Publish darwin/arm64 binaries as GitHub release artifacts. Config templates and a minimal migration set will be included for non-superuser operation.

**Tech Stack:** Nix (packaging), GitHub Actions (CI/CD), PostgreSQL 17, supautils extension

---

## Prerequisites

- Separate minimal migrations will be maintained by CLI team (out of scope for this plan)
- gotrue and postgrest binaries will be fetched from their respective releases (out of scope)
- This plan focuses on the postgres-dev repo changes only

---

### Task 1: Create Minimal Extension List for CLI Package

**Files:**
- Create: `nix/packages/cli-extensions.nix`

**Step 1: Create the minimal extension list file**

```nix
# Minimal extension list for Supabase CLI
# Only includes supautils for non-superuser operation
{
  # Core extension required for Supabase functionality
  cliExtensions = [
    ../ext/supautils.nix
  ];
}
```

**Step 2: Verify file syntax**

Run: `nix eval --file nix/packages/cli-extensions.nix`
Expected: `{ cliExtensions = [ ... ]; }`

**Step 3: Commit**

```bash
git add nix/packages/cli-extensions.nix
git commit -m "feat: add minimal extension list for CLI package"
```

---

### Task 2: Add CLI Package Variants to postgres.nix

**Files:**
- Modify: `nix/packages/postgres.nix`

**Step 1: Import the CLI extension list**

Add after line 47 (after `ourExtensions` definition):

```nix
      # Minimal extensions for CLI package (supautils only)
      cliExtensions = [
        ../ext/supautils.nix
      ];
```

**Step 2: Add extension selection logic in makeOurPostgresPkgs**

Modify `makeOurPostgresPkgs` to accept a `variant` parameter. Replace the existing function (around line 94-122):

```nix
      makeOurPostgresPkgs =
        version:
        {
          latestOnly ? false,
          variant ? "full", # "full", "slim", or "cli"
        }:
        let
          postgresql = getPostgresqlPackage version latestOnly;
          extensionsToUse =
            if variant == "cli" then
              cliExtensions
            else if (builtins.elem version [ "orioledb-17" ]) then
              orioledbExtensions
            else if (builtins.elem version [ "17" ]) then
              dbExtensions17
            else
              ourExtensions;
          extCallPackage = pkgs.lib.callPackageWith (
            pkgs
            // {
              inherit postgresql latestOnly;
              switch-ext-version = extCallPackage ./switch-ext-version.nix { };
              overlayfs-on-package = extCallPackage ./overlayfs-on-package.nix { };
            }
          );
        in
        map (path: extCallPackage path { }) extensionsToUse;
```

**Step 3: Update makeOurPostgresPkgsSet to pass variant**

```nix
      makeOurPostgresPkgsSet =
        version:
        {
          latestOnly ? false,
          variant ? "full",
        }:
        let
          pkgsList = makeOurPostgresPkgs version { inherit latestOnly variant; };
          # ... rest unchanged
```

**Step 4: Update makePostgresBin to pass variant**

```nix
      makePostgresBin =
        version:
        {
          latestOnly ? false,
          variant ? "full",
        }:
        let
          postgresql = getPostgresqlPackage version latestOnly;
          postgres-pkgs = makeOurPostgresPkgs version { inherit latestOnly variant; };
          # ... rest unchanged
```

**Step 5: Update makePostgres to pass variant**

```nix
      makePostgres =
        version:
        {
          latestOnly ? false,
          variant ? "full",
        }:
        lib.recurseIntoAttrs {
          bin = makePostgresBin version { inherit latestOnly variant; };
          exts = makeOurPostgresPkgsSet version { inherit latestOnly variant; };
        };
```

**Step 6: Add CLI package definitions**

Add after `slimPackages` definition:

```nix
      # CLI packages - minimal PostgreSQL + supautils only for Supabase CLI
      cliPackages = {
        psql_15_cli = makePostgres "15" { latestOnly = true; variant = "cli"; };
        psql_17_cli = makePostgres "17" { latestOnly = true; variant = "cli"; };
      };
```

**Step 7: Update binPackages and legacyPackages**

```nix
      binPackages = lib.mapAttrs' (name: value: {
        name = "${name}/bin";
        value = value.bin;
      }) (basePackages // slimPackages // cliPackages);
    in
    {
      packages = binPackages;
      legacyPackages = basePackages // slimPackages // cliPackages;
    };
```

**Step 8: Run nix flake check to verify evaluation**

Run: `nix flake check --no-build 2>&1 | head -50`
Expected: No evaluation errors, should see `psql_15_cli` and `psql_17_cli` in output

**Step 9: Commit**

```bash
git add nix/packages/postgres.nix
git commit -m "feat: add CLI package variants with minimal extensions"
```

---

### Task 3: Create Config Templates for CLI

**Files:**
- Create: `nix/packages/cli-config/postgresql.conf.template`
- Create: `nix/packages/cli-config/pg_hba.conf.template`
- Create: `nix/packages/cli-config/pg_ident.conf.template`

**Step 1: Create postgresql.conf template**

```ini
# Supabase CLI PostgreSQL Configuration
# Minimal configuration for local development

# Connection Settings
listen_addresses = '127.0.0.1'
port = 54322
max_connections = 100

# Memory Settings (conservative for local dev)
shared_buffers = 128MB
effective_cache_size = 256MB
work_mem = 4MB
maintenance_work_mem = 64MB

# Write Ahead Log
wal_level = replica
max_wal_senders = 0

# Logging
log_destination = 'stderr'
logging_collector = off
log_min_messages = warning
log_min_error_statement = error

# Locale
lc_messages = 'C'
lc_monetary = 'C'
lc_numeric = 'C'
lc_time = 'C'

# Extensions
shared_preload_libraries = 'supautils'

# Supautils configuration
supautils.reserved_roles = 'supabase_admin,supabase_auth_admin,supabase_storage_admin,supabase_read_only_user,supabase_replication_admin,supabase_realtime_admin,supabase_functions_admin'
supautils.reserved_memberships = 'pg_read_server_files,pg_write_server_files,pg_execute_server_program'
```

**Step 2: Create pg_hba.conf template**

```ini
# Supabase CLI Host-Based Authentication
# TYPE  DATABASE        USER            ADDRESS                 METHOD

# Local connections
local   all             all                                     trust
# IPv4 local connections
host    all             all             127.0.0.1/32            scram-sha-256
# IPv6 local connections
host    all             all             ::1/128                 scram-sha-256
```

**Step 3: Create pg_ident.conf template**

```ini
# Supabase CLI Ident Map Configuration
# MAPNAME       SYSTEM-USERNAME         PG-USERNAME
```

**Step 4: Commit**

```bash
git add nix/packages/cli-config/
git commit -m "feat: add config templates for CLI package"
```

---

### Task 4: Create CLI Bundle Package

**Files:**
- Create: `nix/packages/cli-bundle.nix`

**Step 1: Create the bundle package**

```nix
{
  lib,
  stdenv,
  writeTextFile,
  symlinkJoin,
  psql_17_cli,
}:
let
  # Config templates
  configDir = ./cli-config;

  # Create a receipt for the CLI bundle
  receipt = writeTextFile {
    name = "cli-receipt";
    destination = "/receipt.json";
    text = builtins.toJSON {
      variant = "cli";
      psql-version = psql_17_cli.bin.version;
      extensions = [ "supautils" ];
      receipt-version = "1";
    };
  };

  # Bundle config templates
  configBundle = stdenv.mkDerivation {
    name = "cli-config-bundle";
    src = configDir;
    installPhase = ''
      mkdir -p $out/share/supabase-cli/config
      cp postgresql.conf.template $out/share/supabase-cli/config/
      cp pg_hba.conf.template $out/share/supabase-cli/config/
      cp pg_ident.conf.template $out/share/supabase-cli/config/
    '';
  };
in
symlinkJoin {
  name = "supabase-postgres-cli";
  version = psql_17_cli.bin.version;
  paths = [
    psql_17_cli.bin
    receipt
    configBundle
  ];

  meta = with lib; {
    description = "Minimal PostgreSQL bundle for Supabase CLI";
    platforms = platforms.unix;
    license = licenses.postgresql;
  };
}
```

**Step 2: Add to packages/default.nix**

Add to the packages attribute set:

```nix
supabase-postgres-cli = pkgs.callPackage ./cli-bundle.nix {
  psql_17_cli = self'.legacyPackages.psql_17_cli;
};
```

**Step 3: Test the bundle builds**

Run: `nix build .#supabase-postgres-cli --print-out-paths`
Expected: Build succeeds, outputs store path

**Step 4: Verify bundle contents**

Run: `ls -la $(nix build .#supabase-postgres-cli --print-out-paths)/`
Expected: Should contain bin/, lib/, share/ directories

**Step 5: Commit**

```bash
git add nix/packages/cli-bundle.nix nix/packages/default.nix
git commit -m "feat: add CLI bundle package with configs"
```

---

### Task 5: Add CLI Package Tests to Checks

**Files:**
- Modify: `nix/checks.nix`

**Step 1: Add CLI check entries**

Add after the slim package checks (around line 460):

```nix
          psql_15_cli = pkgs.runCommand "run-check-harness-psql-15-cli" { } (
            lib.getExe (makeCheckHarness self'.packages."psql_15_cli/bin" { legacyPkgName = "psql_15_cli"; })
          );
          psql_17_cli = pkgs.runCommand "run-check-harness-psql-17-cli" { } (
            lib.getExe (makeCheckHarness self'.packages."psql_17_cli/bin" { legacyPkgName = "psql_17_cli"; })
          );
```

**Step 2: Add CLI ports to port selection**

Update the `pgPort` selection in `makeCheckHarness`:

```nix
              pgPort =
                if effectiveLegacyPkgName == "psql_17_cli" then
                  "5541"
                else if effectiveLegacyPkgName == "psql_15_cli" then
                  "5542"
                else if (majorVersion == "17" && isSlim) then
                  "5538"
                # ... rest unchanged
```

**Step 3: Run format**

Run: `nix fmt`

**Step 4: Run checks to verify CLI packages work**

Run: `nix flake check -L 2>&1 | grep -E "(psql.*cli|PASS|FAIL)"`
Expected: CLI checks should pass (or skip extension tests gracefully)

**Step 5: Commit**

```bash
git add nix/checks.nix
git commit -m "feat: add CLI package checks"
```

---

### Task 6: Create GitHub Workflow for Darwin/ARM64 Release

**Files:**
- Create: `.github/workflows/cli-release.yml`

**Step 1: Create the release workflow**

```yaml
name: CLI Release

on:
  push:
    tags:
      - 'cli-v*'
  workflow_dispatch:
    inputs:
      version:
        description: 'Version tag (e.g., cli-v1.0.0)'
        required: true

jobs:
  build-darwin-arm64:
    runs-on: macos-14  # M1 runner
    steps:
      - uses: actions/checkout@v4

      - uses: DeterminateSystems/nix-installer-action@main

      - uses: DeterminateSystems/magic-nix-cache-action@main

      - name: Build CLI bundle
        run: |
          nix build .#supabase-postgres-cli -o result

      - name: Create tarball
        run: |
          VERSION="${{ github.event.inputs.version || github.ref_name }}"
          mkdir -p dist
          tar -czvf "dist/supabase-postgres-${VERSION}-darwin-arm64.tar.gz" \
            -C result .

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: supabase-postgres-darwin-arm64
          path: dist/*.tar.gz

  build-darwin-x64:
    runs-on: macos-13  # Intel runner
    steps:
      - uses: actions/checkout@v4

      - uses: DeterminateSystems/nix-installer-action@main

      - uses: DeterminateSystems/magic-nix-cache-action@main

      - name: Build CLI bundle
        run: |
          nix build .#supabase-postgres-cli -o result

      - name: Create tarball
        run: |
          VERSION="${{ github.event.inputs.version || github.ref_name }}"
          mkdir -p dist
          tar -czvf "dist/supabase-postgres-${VERSION}-darwin-x64.tar.gz" \
            -C result .

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: supabase-postgres-darwin-x64
          path: dist/*.tar.gz

  build-linux-arm64:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: DeterminateSystems/nix-installer-action@main
        with:
          extra-conf: |
            extra-platforms = aarch64-linux

      - uses: DeterminateSystems/magic-nix-cache-action@main

      - name: Set up QEMU
        uses: docker/setup-qemu-action@v3

      - name: Build CLI bundle for ARM64
        run: |
          nix build .#supabase-postgres-cli \
            --system aarch64-linux \
            -o result

      - name: Create tarball
        run: |
          VERSION="${{ github.event.inputs.version || github.ref_name }}"
          mkdir -p dist
          tar -czvf "dist/supabase-postgres-${VERSION}-linux-arm64.tar.gz" \
            -C result .

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: supabase-postgres-linux-arm64
          path: dist/*.tar.gz

  build-linux-x64:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: DeterminateSystems/nix-installer-action@main

      - uses: DeterminateSystems/magic-nix-cache-action@main

      - name: Build CLI bundle
        run: |
          nix build .#supabase-postgres-cli -o result

      - name: Create tarball
        run: |
          VERSION="${{ github.event.inputs.version || github.ref_name }}"
          mkdir -p dist
          tar -czvf "dist/supabase-postgres-${VERSION}-linux-x64.tar.gz" \
            -C result .

      - name: Upload artifact
        uses: actions/upload-artifact@v4
        with:
          name: supabase-postgres-linux-x64
          path: dist/*.tar.gz

  release:
    needs: [build-darwin-arm64, build-darwin-x64, build-linux-arm64, build-linux-x64]
    runs-on: ubuntu-latest
    if: startsWith(github.ref, 'refs/tags/')
    permissions:
      contents: write
    steps:
      - name: Download all artifacts
        uses: actions/download-artifact@v4
        with:
          path: artifacts

      - name: Create Release
        uses: softprops/action-gh-release@v1
        with:
          files: artifacts/**/*.tar.gz
          generate_release_notes: true
```

**Step 2: Commit**

```bash
git add .github/workflows/cli-release.yml
git commit -m "feat: add GitHub workflow for CLI releases"
```

---

### Task 7: Add Documentation

**Files:**
- Create: `docs/cli-bundle.md`

**Step 1: Create documentation**

```markdown
# Supabase CLI PostgreSQL Bundle

This document describes the minimal PostgreSQL bundle designed for use with the Supabase CLI.

## Overview

The CLI bundle provides a minimal PostgreSQL installation with only the essential extension (supautils) required for Supabase functionality. This enables local development without Docker.

## Contents

The bundle includes:

- **PostgreSQL 17** - Core database binaries
- **supautils** - Extension for Supabase role management
- **Config templates** - Pre-configured postgresql.conf, pg_hba.conf, pg_ident.conf

## Building Locally

```bash
# Build the CLI bundle
nix build .#supabase-postgres-cli

# The result will be in ./result/
ls ./result/
# bin/  lib/  share/  receipt.json
```

## Package Variants

| Package | Extensions | Use Case |
|---------|------------|----------|
| `psql_17` | All 36 extensions | Full deployment |
| `psql_17_slim` | Latest versions only | Smaller Docker images |
| `psql_17_cli` | supautils only | Supabase CLI |

## Config Templates

Located in `share/supabase-cli/config/`:

- `postgresql.conf.template` - Conservative settings for local dev
- `pg_hba.conf.template` - Local-only access with scram-sha-256
- `pg_ident.conf.template` - Empty ident map

## Initializing a Database

```bash
# Set paths
export PGDATA=/path/to/data
export BUNDLE=/path/to/bundle

# Initialize
$BUNDLE/bin/initdb -D $PGDATA

# Copy config
cp $BUNDLE/share/supabase-cli/config/postgresql.conf.template $PGDATA/postgresql.conf
cp $BUNDLE/share/supabase-cli/config/pg_hba.conf.template $PGDATA/pg_hba.conf

# Start
$BUNDLE/bin/pg_ctl -D $PGDATA start

# Create supautils extension
$BUNDLE/bin/psql -c "CREATE EXTENSION supautils;"
```

## Migrations

The CLI team maintains a separate minimal migration set. See the Supabase CLI repository for migration details.

## Release Artifacts

Published to GitHub Releases with tag pattern `cli-v*`:

- `supabase-postgres-cli-v*-darwin-arm64.tar.gz`
- `supabase-postgres-cli-v*-darwin-x64.tar.gz`
- `supabase-postgres-cli-v*-linux-arm64.tar.gz`
- `supabase-postgres-cli-v*-linux-x64.tar.gz`
```

**Step 2: Commit**

```bash
git add docs/cli-bundle.md
git commit -m "docs: add CLI bundle documentation"
```

---

### Task 8: Final Integration Test

**Step 1: Build all CLI variants**

Run:
```bash
nix build .#psql_15_cli/bin -o result-15
nix build .#psql_17_cli/bin -o result-17
nix build .#supabase-postgres-cli -o result-bundle
```

Expected: All builds succeed

**Step 2: Verify bundle contents**

Run:
```bash
echo "=== Binaries ==="
ls result-bundle/bin/ | head -10

echo "=== Extensions ==="
ls result-bundle/lib/postgresql/ 2>/dev/null || ls result-bundle/lib/*.so 2>/dev/null | head -5

echo "=== Config templates ==="
ls result-bundle/share/supabase-cli/config/

echo "=== Receipt ==="
cat result-bundle/receipt.json
```

Expected:
- Binaries: postgres, initdb, pg_ctl, psql, etc.
- Extensions: supautils.so (or .dylib on macOS)
- Config: postgresql.conf.template, pg_hba.conf.template, pg_ident.conf.template
- Receipt: JSON with variant="cli" and extensions=["supautils"]

**Step 3: Test database initialization**

Run:
```bash
PGDATA=$(mktemp -d)
./result-bundle/bin/initdb -D $PGDATA
./result-bundle/bin/pg_ctl -D $PGDATA -l $PGDATA/logfile start -w
./result-bundle/bin/psql -h localhost -c "SELECT version();"
./result-bundle/bin/psql -h localhost -c "CREATE EXTENSION supautils;"
./result-bundle/bin/psql -h localhost -c "SELECT * FROM pg_extension WHERE extname = 'supautils';"
./result-bundle/bin/pg_ctl -D $PGDATA stop
rm -rf $PGDATA
```

Expected: All commands succeed, supautils extension created

**Step 4: Run nix flake check**

Run: `nix flake check -L`

Expected: All checks pass

**Step 5: Final commit**

```bash
git add -A
git commit -m "feat: complete CLI bundle implementation"
```

---

## Summary

After completing all tasks, you will have:

1. **New packages:**
   - `psql_15_cli` - PostgreSQL 15 + supautils
   - `psql_17_cli` - PostgreSQL 17 + supautils
   - `supabase-postgres-cli` - Complete bundle with configs

2. **Config templates** in `nix/packages/cli-config/`

3. **GitHub workflow** for building and releasing darwin/arm64 + linux binaries

4. **Documentation** at `docs/cli-bundle.md`

5. **Tests** integrated into `nix flake check`

## Next Steps (CLI Team)

1. Create minimal migrations in CLI repo
2. Integrate bundle download into CLI
3. Add orchestration for postgres + gotrue + postgrest
4. Fetch gotrue/postgrest from their respective releases
