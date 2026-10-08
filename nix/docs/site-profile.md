# Site profile

The `site-env-15`, `site-env-17`, and `site-env-orioledb-17` package sets are deployed to `/nix/var/nix/profiles/site`. They hold supautils, `activate`, and `site-nix-gc`.

`dynamic_library_path` in `postgresql.conf` includes `/nix/var/nix/profiles/site/pg-extensions` first, then `$libdir`. supautils also remains in `$libdir`, pending cleanup.

## Publish

`ami-release-nix.yml` uploads each store path as a string to the public artifacts bucket, in the object `nix-catalog/<sha>-site-env-<major>-<system>`. Release branches also upload the git sha as a string to `latest-site-env-<major>-<system>.sha`. The AMI bake installs the env and runs `activate`.

## Update

```sh
nix-env --profile /nix/var/nix/profiles/site --set <store path>
/nix/var/nix/profiles/site/bin/activate
```

`--set` downloads the path if it is missing. `activate` prunes the profile to its last two generations and starts a throttled `nix-store --gc` through systemd. The GC is skipped without systemd. `activate` must stay idempotent.

## Roll back

```sh
nix-env --profile /nix/var/nix/profiles/site --rollback
```

`activate` keeps two generations, so one rollback step is always available.

## Test

```sh
nix build .#checks.<system>.site -L
```

The `site` VM test covers loading supautils from the site profile, the `$libdir` fallthrough, and `activate`.
