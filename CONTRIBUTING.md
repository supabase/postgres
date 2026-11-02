# Welcome to Supabase Postgres contributing guide

## Adding a new extension

Extensions are built with Nix. Follow [Adding new packages](nix/docs/adding-new-package.md).

## Testing an extension

Extensions can be tested automatically using pgTAP. Start by creating a new file in [migrations/tests/extensions](migrations/tests/extensions). For example:

```sql
BEGIN;
create extension if not exists wrappers with schema "extensions";
ROLLBACK;
```

This test runs as part of `nix flake check` and checks that your extension can be enabled.
