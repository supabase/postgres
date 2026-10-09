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

`--set` downloads the path if it is missing. `activate` sets up supautils, and gatekeeper where present, idempotently.

`site-nix-gc` keeps the last 3 site profile generations and the last 2 postgres and default profile generations. It then runs `nix-store --gc` in a throttled transient systemd unit, which is skipped without systemd.

## Roll back

```sh
nix-env --profile /nix/var/nix/profiles/site --rollback
```

Rollback switches to the previous generation. `site-nix-gc` keeps the last 3.

## Test

```sh
nix build .#checks.<system>.site -L
```

The `site` VM test covers loading supautils from the site profile, the `$libdir` fallthrough, and `activate`.
