# Usage

From the root of the `supabase/postgres` project, you can run the following commands:

```shell
Usage: nix run .#dbmate-tool -- [options]

Options:
  -v, --version [15|17|orioledb-17|all]  PostgreSQL version to regenerate the schema for, repeatable (default: all)
  -f, --flake-url URL                    Flake to build the schema from (default: .)
  -h, --help                             Show this help message

Description:
  Builds schema-dump-<version>, which runs the init scripts and migrations with dbmate against a
  throwaway Postgres and dumps the schema, then copies the dump to migrations/schema-<version>.sql.
  CI checks that file against the same package. Run it from the root of the repository.
  NOTE: To create a migration, you must run 'nix develop' and then 'dbmate new <migration_name>' to create a new migration file.

Examples:
  nix run .#dbmate-tool
  nix run .#dbmate-tool -- --version 15
  nix run .#dbmate-tool -- --version 17 --flake-url github:supabase/postgres/<commithash>

```

## supabase/migrations

`supabase/migrations` is a consolidation of SQL migrations from:

- supabase/postgres
- supabase/supabase
- supabase/cli
- supabase/platform (internal)

aiming to provide a single source of truth for migrations on the platform that those components can depend on.
For more information on goals see [the RFC](https://www.notion.so/supabase/Centralize-SQL-Migrations-cd3847ae027d4f2bba9defb2cc82f69a)

### Where the migrations came from

We pulled the migrations, in order, from:

1. [init-scripts/postgres](https://github.com/supabase/platform/tree/develop/init-scripts/postgres) => [db/init-scripts](db/init-scripts)
2. [init-scripts/migrations](https://github.com/supabase/platform/tree/develop/init-scripts/migrations) => [db/migrations](db/migrations)

For compatibility with hosted projects, we include [migrate.sh](db/migrate.sh), which runs the migrations in the same order as the AMI build:

1. Run all `db/init-scripts` with `postgres` superuser role.
2. Run all `db/migrations` with `supabase_admin` superuser role.
3. Set role passwords with `/etc/postgresql.schema.sql`, if it exists.

Additionally, [supabase/postgres](https://github.com/supabase/postgres/blob/develop/ansible/playbook-docker.yml#L9) image contains several migration scripts to configure default extensions.
The Docker entrypoint runs these first, and Ansible includes them in the AMI.

### Where migrations run

The SQL files in `db/` set up a new, empty database.
This repository uses them for nothing else.
Most uses run them through [migrate.sh](db/migrate.sh):

Nothing in this repository applies new migrations to a database that is already running.

| Where                                                      | When                                                                                                              |
| ---------------------------------------------------------- | ----------------------------------------------------------------------------------------------------------------- |
| AMI and qemu builds (`ansible/tasks/setup-migrations.yml`) | Stage 2 of the image build. The image keeps the result.                                                           |
| Docker images (`Dockerfile-*`)                             | The first time a container starts with an empty data directory.                                                   |
| CLI package (`nix/packages/postgres-portable.nix`)         | `cli-release.yml` runs it. The package ships a copy for the CLI.                                                  |
| `nix/packages/schema-dump`                                 | It runs the migrations to dump the schema, then runs them a second time to check that they are safe to run again. |

### Other files in this directory

- `tests/` holds the pgTAP tests.
  `nix flake check` runs them against a Postgres built by Nix (see `nix/checks.nix`).
  No image includes them.
- `schema-<version>.sql` is a saved copy of the schema that `db/` creates, one for each Postgres version.
  It comes from `schmea-dump-<version>` nix package.
  It lets a reviewer see what a migration changes.
  CI (`schema-check-<version>`) fails when the file no longer matches the migrations.
  Nothing loads it into a database.
  It has no owners, grants, or data, so it cannot replace the migrations.

### Guidelines

- Migrations are append only.
  Never edit existing migrations once they are on master.
- Migrations in `migrations/db/migrations` have to be idempotent.
- Self-contained components (gotrue, storage, realtime) may contain their own migrations.
- Self-hosted Supabase users should update role passwords separately after running all migrations.

### Usage

#### Add a Migration

First, start a local postgres server in another terminal window:

```shell
# Start the database server in another window
nix run .#start-server 15
```

Then, in your main terminal window, run:

```shell
nix develop
```

Next run:

```shell
# Create a new migration (make sure to specify the migrations directory)
dbmate --migrations-dir="migrations/db/migrations" new '<some message>'
```

Then, execute the migration at `./migrations/db/xxxxxxxxx_<some_message>` and make sure it runs successfully with:

```shell
# Make sure DATABASE_URL is set, or use the -u flag to specify the database connection
# Example with DATABASE_URL:
dbmate --no-dump-schema --migrations-dir="migrations/db/migrations" up

# Or with -u flag:
dbmate --no-dump-schema --migrations-dir="migrations/db/migrations" -u "postgres://supabase_admin:postgres@localhost:5435/postgres?sslmode=disable" up
```

Note: Run migrations as the `supabase_admin` superuser, as the "Where the migrations came from" section above explains.

#### Updating schema.sql for each major version

After making changes to migrations, you should update the schema.sql files for each major version of PostgreSQL:

> **Note:** Run `git add migrations/db/migrations/<migration_file>` on every new migration file before you run the command below.
> The local flake sees only files that git tracks, so it silently skips new ones.

```shell
nix run .#dbmate-tool
```

This creates a `schema-<ver>.sql` file for each major version of PostgreSQL and OrioleDB.
Commit these changes to your branch.
The `schema-<version>` nix checks rebuild the schema in CI and fail if the committed files differ.

### Testing

CI also tests the migrations.
To test them locally, run the following for each major Postgres version, one at a time.

Examples:

```shell
nix build .#checks.aarch64-darwin.psql_15 -L
nix build .#checks.aarch64-darwin.psql_17 -L
nix build .#checks.aarch64-darwin.psql_orioledb-17 -L
```

(Note that the postgres "bundle" for each major version must evaluate and build here, even though you run one version at a time.
If you made changes to postgres or extensions, or wrappers those may rebuild here when you run this.
Otherwise they will usually download the prebuilt version from the supabase nix binary cache)

At the end of these commands, you will see the output of both `pg_regress` tests, and migration tests

see [Adding Tests](https://github.com/supabase/postgres/blob/develop/nix/docs/adding-tests.md) for more information.
