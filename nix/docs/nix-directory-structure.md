# Nix Directory Structure

This document explains the Nix structure used in this repository. The project uses [flake-parts](https://flake.parts/) to split a `flake.nix` into specialized, maintainable modules.

The root `flake.nix` serves only as an entry point that references specialized modules in the `nix/` directory:

```
├── flake.nix                  # Root flake file only referencing modules
nix/
 ├── apps.nix                 # Application definitions
 ├── checks.nix               # Build checks and tests
 ├── config.nix               # Global configuration
 ├── devShells.nix            # Development environment shell
 ├── fmt.nix                  # Code formatting configuration
 ├── hooks.nix                # Git hooks and pre-commit
 ├── ext/                     # PostgreSQL extensions
 ├── overlays/                # Nixpkgs overlays
 ├── packages/                # Custom packages
 └── postgresql/              # PostgreSQL packages
```

## Module Descriptions

### Root Files

#### `flake.nix`

The main flake file that:

- Declares inputs (nixpkgs, flake-parts, etc.)
- Sets up the systems to support (x86_64-linux, aarch64-linux, aarch64-darwin)
- Imports all module files using flake-parts

#### `flake.lock`

Lockfile containing exact versions of all flake inputs.

### Core Configuration Modules

#### `nix/config.nix`

Global configuration and constants used throughout the flake:

- PostgreSQL default ports and users
- System-wide package configurations
- Shared constants and variables

#### `nix/nixpkgs.nix`

Nixpkgs configuration:

- System-specific package imports
- Overlay applications
- Package configuration (allow unfree packages, etc.)

### Development Environment

#### `nix/devShells.nix`

Development shell configurations:

- Default development environment
- Tool dependencies for development
- Environment variables and setup

#### `nix/fmt.nix`

Code formatting configuration using [treefmt](https://github.com/numtide/treefmt/):

- nixfmt-rfc-style for Nix code formatting
- deadnix for removing unused nix code

More details in [Formatting and pre-commit hooks](./nix-formatter.md).

#### `nix/hooks.nix`

Git hooks and pre-commit configuration:

- Integration with [git-hooks.nix](https://github.com/cachix/git-hooks.nix)
- Automatic formatting on commit
- Code quality checks

More details in [Formatting and pre-commit hooks](./nix-formatter.md).

### Applications and Packages

#### `nix/apps.nix`

Application definitions accessible via `nix run`:

- Development tools and scripts
- Build and deployment utilities
- Testing and validation tools

#### `nix/packages/`

Directory containing custom package definitions such as:

  - `default.nix` - Main package exports and basePackages
  - `start-client.nix` - PostgreSQL client tools
  - `start-replica.nix` - Replication tools
  - `migrate-tool.nix` - Migration utilities
  - `dbmate-tool.nix` - Database migration tool
  - `postgres.nix` - Postgres extension registry and ourExtensions list

#### `nix/checks.nix`

Build checks and validation:

- Package build validation
- Integration tests
- Code quality checks
- Ensures all Postgres packages build correctly

### PostgreSQL-Specific

#### `nix/postgresql/`

PostgreSQL package definitions:

- `default.nix` - Main PostgreSQL package exports
- `generic.nix` - Generic PostgreSQL build functions
- `src.nix` - PostgreSQL source package generation
- `patches/` - PostgreSQL-specific patches

#### `nix/ext/`

PostgreSQL extensions:

- Individual `.nix` files - Extension definitions like:
  - `pgvector.nix` - Vector similarity search
  - `pgsodium.nix` - Encryption extension
  - `pg_graphql.nix` - GraphQL support
  - `timescaledb.nix` - Time-series database
  - And 30+ other extensions

### System Customization

#### `nix/overlays/`

[Nixpkgs overlays](https://nixos.org/manual/nixpkgs/stable/#chap-overlays) for package customization.
`default.nix` defines the single overlay and applies it in `nix/nixpkgs.nix`.

The overlay exposes the OrioleDB build as `postgresql_orioledb-17`, a separate patched Postgres fork.
Build it with `nix build .#psql_orioledb-17.bin`.

#### `nix/cargo-pgrx/`

Rust-based PostgreSQL extension building:

- `default.nix` - cargo-pgrx package definitions
- `buildPgrxExtension.nix` - Builder for Rust extensions

### Testing

#### `nix/tests/`

Test suites and expected outputs:

- `sql/` - SQL test files
- `expected/` - Expected test outputs
- `migrations/` - Migration test data
- `smoke/` - Smoke tests for quick validation

## How the modules connect

- `nix/nixpkgs.nix` sets `_module.args.pkgs` with the overlays applied. Every other module gets `pkgs` from it.
- `nix/config.nix` defines `self.supabase`, which holds `defaults` (port, host, superuser) and `supportedPostgresVersions`.
- `nix/overlays/default.nix` re-exports our `postgresql_*` packages into `pkgs`.
- `nix/packages/postgres.nix` builds `psql_<version>`. `packages` holds the flat `"psql_15/bin"` names. `legacyPackages` holds the nested sets, so `nix build .#psql_15.exts.rum` works.
- `apps.nix`, `devShells.nix`, and `checks.nix` read packages through `self'.packages`. `self'` and `inputs'` are the current-system views of `self` and `inputs`.
- `hooks.nix` uses `config.treefmt.build.wrapper` from `fmt.nix`.
