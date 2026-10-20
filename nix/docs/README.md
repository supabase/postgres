# Documentation

This directory contains most of the "runbooks" and documentation on how to use
this repository.

## Getting Started

You probably want to start with the [starting guide](./start-here.md). Then,
learn how to play with `postgres` in the [build guide](./build-postgres.md).

## Development

- **[Nix tree structure](./nix-directory-structure.md)** - Overview of the Nix directory structure
- **[Development Workflow](./development-workflow.md)** - Complete development and testing workflow
- **[Build PostgreSQL](./build-postgres.md)** - Building PostgreSQL from source
- **[Receipt Files](./receipt-files.md)** - Understanding build receipts
- **[Start Client/Server](./start-client-server.md)** - Running PostgreSQL client and server
- **[Docker](./docker.md)** - Docker integration and usage
- **[Multigres image](https://github.com/supabase/postgres/blob/develop/docs/multigres-image.md)** - Building the multigres Docker image
- **[Docker Image Size Analyzer](./image-size-analyzer-usage.md)** - Tool to analyze the Docker image sizes
- **[Formatting and pre-commit hooks](./nix-formatter.md)** - Code formatting with treefmt and git hooks
- **[Create a New pgrx Extension](./creating-pgrx-extension.md)** - How to set up a new cargo pgrx extension
- **[Updating pgrx Extensions](./updating-pgrx-extensions.md)** - How to upgrade the cargo pgrx extensions

## Package Management

- **[Adding New Packages](./adding-new-package.md)** - How to add new PostgreSQL extensions
- **[Update Extensions](./update-extension.md)** - How to update existing extensions
- **[Update Nix Dependecies](./updating-dependencies.md)** - How to update the Nix dependencies
- **[New Major PostgreSQL](./new-major-postgres.md)** - Adding support for new PostgreSQL versions

## Testing

- **[Adding Tests](./adding-tests.md)** - How to add tests for extensions
- **[Migration Tests](./migration-tests.md)** - Testing database migrations
- **[Testing PG Upgrade Scripts](./testing-pg-upgrade-scripts.md)** - Testing PostgreSQL upgrades
- **[Docker Image testing](./docker-testing.md)** - How to test the docker images against the pg_regress test suite.

## CI

- **[Nix Build Matrix](./nix-build-matrix-ci.md)** - Understand how the CI Nix build matrix works

## Reference

- **[References](./references.md)** - Useful links and resources

## Documentation

The docs are Markdown in `nix/docs`, rendered with [mkdocs](https://www.mkdocs.org/). Run `serve-nix-doc` in a development shell to preview them at `http://localhost:8000`. The configuration is in `nix/mkdocs.yml`.
