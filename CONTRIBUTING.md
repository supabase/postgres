# Welcome to Supabase Postgres contributing guide

## Adding a New Extension

Supabase Postgres supports multiple Dockerfiles for different versions and deployment scenarios (e.g., `Dockerfile-15`, `Dockerfile-17`, `Dockerfile-kubernetes`, `Dockerfile-orioledb-17`).  

> Instructions for [adding extensions](https://github.com/supabase/postgres/blob/develop/nix/docs/adding-new-package.md)

Here's a minimal example:

```dockerfile
ARG pg_graphql_release=1.1.0

####################
# 19-pg_graphql.yml
####################
FROM base as pg_graphql
# Download package archive
ARG pg_graphql_release
ADD "https://github.com/supabase/pg_graphql/releases/download/v${pg_graphql_release}/pg_graphql-v${pg_graphql_release}-pg${postgresql_major}-${TARGETARCH}-linux-gnu.deb" \
    /tmp/pg_graphql.deb

####################
# Collect extension packages
####################
FROM scratch as extensions
COPY --from=pg_graphql /tmp/*.deb /tmp/
```

Using this process maximises the effectiveness of Docker layer caching, which significantly speeds up our CI builds.

## Testing an extension

Extensions can be tested automatically using pgTAP. Start by creating a new file in [migrations/tests/extensions](migrations/tests/extensions). For example:

```sql
BEGIN;
create extension if not exists wrappers with schema "extensions";
ROLLBACK;
```

This test will be run as part of CI to check that your extension can be enabled successfully from the final Docker image.
