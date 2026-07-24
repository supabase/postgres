# nix/tests — pg_regress suite against the platform configuration

These tests run on every PR via `nix flake check` (see `nix/checks.nix`).
The `sql/` + `expected/` pairs are executed pg_regress-style against a
server started by `start-postgres-server` (`nix/tools/run-server.sh.in`),
which closely matches what ships on the AMI:

- the **rendered platform `supautils.conf`** is loaded
  (`ansible/files/postgresql_config/supautils.conf.j2`, with only the
  custom-scripts path substituted), and supautils is in
  `session_preload_libraries`
- the **real migrations** run (`migrations/db`), so the platform role
  topology exists: `postgres` (not a superuser), `anon`, `authenticated`,
  `service_role`, the reserved roles, etc.
- the suite connects as `supabase_admin`, the bootstrap **superuser** of
  the test cluster
- `prime.sql` pre-creates the platform extension set before any test runs

This means changes to `supautils.conf.j2` are live in this suite on the
same PR that makes them — conf changes and their tests should travel
together.

## Testing platform policy (supautils behavior for real roles)

Because the session user is a superuser (and superusers are exempt from
most supautils restrictions), policy tests must switch to the role the
policy targets:

```sql
set role postgres;
-- statements exercising the restriction / delegation / grant
reset role;
```

Conventions for policy tests:

- **Restore the primed state.** Tests share one cluster and run in
  filename order; if you drop or alter something `prime.sql` created
  (e.g. an extension), recreate it in its default state at the end of
  your file.
- **Keep assertions version-agnostic** where extension versions are
  involved — e.g. compare against `pg_available_extensions.default_version`
  instead of printing a version number, or suppress version-bearing
  NOTICEs with `set client_min_messages = warning`. Version-specific
  behavior belongs in `z_<ver>_*.sql` files, which only run for that
  Postgres major.
- **Regenerating expected output:** run the same server locally
  (`nix run .#start-postgres-server -- --daemonize <major>`), apply your
  sql file with `psql -U supabase_admin`, and use the output; or take the
  `regression_output` artifact from the failed CI check.

Examples: `supautils_platform_policy.sql` (extension delegation) and
`supautils_reserved_roles.sql` (reserved-role protection, using the
BEGIN/SAVEPOINT pattern to recover from an expected error mid-file).

## What does NOT belong here

- supautils *logic* tests (all GUC modes, statement variants) — those
  live in the supautils repo's own regress suite.
- Artifact wiring checks (is the conf present on the built AMI, services
  up, apparmor) — those live in `testinfra/` and run against a real EC2
  instance of the AMI.
