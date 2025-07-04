# Welcome to Supabase Postgres contributing guide

## Adding a New Extension

Supabase Postgres supports multiple Dockerfiles for different versions and deployment scenarios (e.g., `Dockerfile-15`, `Dockerfile-17`, `Dockerfile-kubernetes`, `Dockerfile-orioledb-17`).  
**Please add your extension to each relevant Dockerfile according to the images you want to support.**

### Steps

1. **Add a build stage** for your extension in the target Dockerfile, named after your extension.  
   _Tip: Search for `FROM base as` in the Dockerfile to find all extension build stages._
2. **Add build arguments** for your extension's release version if needed.
3. **Download or build the extension package** (`.deb`) in your build stage and place it in `/tmp/`.
   - If your extension is published as a `.deb` package, use `ADD` or `COPY`.
   - If you need to build from source, use `checkinstall` or a similar tool to create a `.deb` package.
4. **In the `extensions` stage**, use `COPY --from=your_stage` to copy your package into the final image.

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
