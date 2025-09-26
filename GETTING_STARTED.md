# Getting Started with Supabase Postgres

This guide covers getting up and running with Supabase Postgres. After reading this guide, you will understand:

* What Supabase Postgres provides and why you might want to use it
* How the project is organized and what each directory contains
* How to build and run Postgres with extensions locally
* The basics of working with the extension ecosystem

---

## What is Supabase Postgres?

Supabase Postgres is a batteries-included PostgreSQL distribution that provides unmodified PostgreSQL with a curated set of the most useful extensions pre-installed. Think of it as PostgreSQL with superpowers - you get the reliability and power of standard PostgreSQL, plus immediate access to extensions for tasks like:

* Full-text search and indexing
* Geospatial data processing
* Time-series data management
* JSON validation and GraphQL support
* Cryptography and security
* Message queuing
* And much more

The goal is simple: make it fast and easy to get started with a production-ready PostgreSQL setup without having to hunt down, compile, and configure dozens of extensions yourself.

## Philosophy

Supabase Postgres follows these core principles:

1. **Unmodified PostgreSQL** - We don't fork or modify PostgreSQL itself. You get standard PostgreSQL with extensions.
2. **Curated Extensions** - We include well-maintained, production-tested extensions that solve real problems.
3. **Multi-version Support** - Currently supporting PostgreSQL 15, 17, and OrioleDB-17.
4. **Ready for Production** - Configured with sensible defaults for replication, security, and performance.
5. **Open Source** - Everything is open source and can be self-hosted.

## Directory Structure

Here's a comprehensive overview of the project's directory structure:

| File/Directory | Purpose |
| -------------- | ------- |
| **nix/** | Core build system directory containing all Nix expressions for building PostgreSQL and extensions |
| nix/postgresql/ | PostgreSQL version configurations, patches, and base package definitions |
| nix/ext/ | Individual extension package definitions and build configurations |
| nix/ext/wrappers/ | Wrapper scripts and utilities for extensions |
| nix/ext/tests/ | Extension-specific test suites |
| nix/overlays/ | Nix overlays for customizing and overriding package definitions |
| nix/tools/ | Build tools, utilities, and helper scripts |
| nix/docker/ | Docker image build definitions using Nix |
| nix/tests/ | Comprehensive integration test suites for validating builds |
| nix/tests/smoke/ | Quick smoke tests for basic functionality |
| nix/tests/migrations/ | Migration and upgrade test scenarios |
| nix/tests/expected/ | Expected `pg_regress` test outputs for validation |
| nix/tests/sql/ | SQL test scripts that are run in `pg_regress` tests |
| nix/docs/ | Build system documentation |
| **ansible/** | Infrastructure as Code for server configuration and deployment of production hosted AWS AMI image |
| ansible/playbook.yml | Main Ansible playbook for PostgreSQL/PostgREST/pgbouncer/Auth server setup |
| ansible/tasks/ | Modular Ansible tasks for specific configuration steps |
| ansible/files/ | Static files, scripts, and templates used by Ansible |
| ansible/vars.yml | AMI version tracking, legacy package version tracking |
| **migrations/** | Database migration management and upgrade tools |
| migrations/db/ | Database schema migrations |
| migrations/db/migrations/ | Individual migration files |
| migrations/db/init-scripts/ | Database initialization scripts |
| migrations/tests/ | Migration testing infrastructure |
| migrations/tests/database/ | Database-specific migration tests |
| migrations/tests/storage/ | Storage-related migration tests |
| migrations/tests/extensions/ | Extension migration tests |
| **docker/** | Container definitions and Docker-related files |
| docker/nix/ | Nix-based Docker build configurations |
| Dockerfile-15 | Docker image definition for PostgreSQL 15 |
| Dockerfile-17 | Docker image definition for PostgreSQL 17 |
| **tests/** | Integration and system tests |
| testinfra/ | Infrastructure tests using pytest framework |
| tests/ | General integration test suites |
| **scripts/** | Utility scripts for development and deployment |
| **docs/** | Additional documentation, images, and resources |
| **ebssurrogate/** | AWS EBS surrogate building for AMI creation |
| **http/** | HTTP-related configurations and files |
| **rfcs/** | Request for Comments - design documents and proposals |
| **db/** | Database-related utilities and configurations |
| **.github/** | GitHub-specific configurations (Actions, templates, etc.) |
| **Root Config Files** |  |
| .gitignore | Git ignore patterns |
| .envrc.recommended | Recommended environment variables for development |
| ansible.cfg | Ansible configuration |
| amazon-arm64-nix.pkr.hcl | Packer configuration for AWS ARM64 builds |
| common-nix.vars.pkr.hcl | Common Packer variables |
| development-arm.vars.pkr.hcl | ARM development environment variables |
| CONTRIBUTING.md | Contribution guidelines |
| README.md | Main project documentation |

## Key Concepts

### Extensions

Extensions are the superpower of PostgreSQL. They add functionality without modifying the core database. Supabase Postgres includes dozens of pre-built extensions covering:

* **Data Types & Validation** - pg_jsonschema, pg_hashids
* **Search & Indexing** - pgroonga, rum, hypopg
* **Geospatial** - PostGIS, pgrouting
* **Time-series** - TimescaleDB
* **Security** - pgsodium, vault, pgaudit
* **Development** - pgtap, plpgsql_check
* **And many more...**

### Multi-version Support

The project supports multiple PostgreSQL versions simultaneously:

* **PostgreSQL 15** - Stable, battle-tested version
* **PostgreSQL 17** - Latest features and improvements
* **OrioleDB-17** - Experimental storage engine for PostgreSQL 17

Each version has its own set of compatible extensions defined in the Nix build system.

### Build System (Nix)

The project uses Nix as its build system, which provides:

* **Reproducible Builds** - Same input always produces the same output
* **Declarative Configuration** - Define what you want, not how to build it
* **Dependency Management** - Automatic handling of complex dependency trees
* **Cross-platform Support** - Build for Linux, macOS, and more

## Common Tasks

### Building Locally

To build PostgreSQL with extensions locally:

```bash
# Build PostgreSQL 15 with extensions
nix build .#psql_15/bin

# Build PostgreSQL 17
nix build .#psql_17/bin

# Build a specific extension
nix build .#psql_17/exts/pg_graphql
```

### Running Tests

```bash
# Run all tests
nix flake check -L

# Run specific test suite (for macos apple silicon for example)
nix build .#checks.aarch64-darwin.psql_17 -L
```

### Creating Docker Images

```bash
# Build Docker image for PostgreSQL 15
docker build -f Dockerfile-15 -t supabase-postgres:15 .

# Build Docker image for PostgreSQL 17
docker build -f Dockerfile-17 -t supabase-postgres:17 .
```

## Next Steps

Now that you understand the basics of Supabase Postgres:

* Check the [Installation Guide](https://github.com/supabase/postgres/wiki) for deployment options
* Explore the [Extension Documentation](#) to learn about available extensions
* Review [Contributing Guidelines](CONTRIBUTING.md) if you want to contribute
* Join the [Supabase Community](https://github.com/supabase/postgres/discussions) for questions and discussions

## Getting Help

* **GitHub Issues** - For bugs and feature requests
* **Discussions** - For questions and general discussion
* **Wiki** - For detailed documentation
* **Discord** - For real-time chat with the community

---

Remember: This is the same PostgreSQL build that powers [Supabase](https://supabase.io), battle-tested in production by thousands of projects.