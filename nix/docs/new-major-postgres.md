# Adding a new major PostgreSQL version

Versions are pinned in this repository. To add a major version `XX`:

- Add `XX` with a `version` and `hash` to `supabase.supportedPostgresVersions.postgres` in `nix/config.nix`. `nix/postgresql/` builds `postgresql_XX` from it.
- Add patches to `nix/postgresql/patches/` if the source needs them.
- Add `psql_XX` to `basePackages` and `psql_XX_slim` to `slimPackages` in `nix/packages/postgres.nix`.
- Add the `psql_XX` aliases in `nix/packages/default.nix` and the checks in `nix/checks.nix`.
- Teach the tools that take a version about `XX`. Search for `psql_17` under `nix/packages/` to find them.
- Add a `Dockerfile-XX` and the release entries in `ansible/vars.yml`.
- Add the version to the GitHub Actions workflows.

Run `nix flake check -L` to test the build.
