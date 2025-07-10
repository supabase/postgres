# Welcome to Supabase Postgres contributing guide

## Adding a New Extension

Supabase Postgres supports multiple Dockerfiles for different versions and deployment scenarios (e.g., `Dockerfile-15`, `Dockerfile-17`, `Dockerfile-kubernetes`, `Dockerfile-orioledb-17`).  

> Instructions for [adding extensions](https://github.com/supabase/postgres/blob/develop/nix/docs/adding-new-package.md)

## Testing an extension

Extensions can be tested automatically using pgTAP. Start by creating a new file in [migrations/tests/extensions](migrations/tests/extensions). For example:

```sql
BEGIN;
create extension if not exists wrappers with schema "extensions";
ROLLBACK;
```

This test will be run as part of CI to check that your extension can be enabled successfully from the final Docker image.
