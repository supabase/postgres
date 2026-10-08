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

`--set` downloads the path if it is missing. `activate` prints what the profile provides. It does not delete generations or collect garbage. `activate` must stay idempotent.

`site-nix-gc` runs `nix-store --gc` in a throttled transient systemd unit. It is skipped without systemd.

## Roll back

```sh
nix-env --profile /nix/var/nix/profiles/site --rollback
```

Rollback switches to the previous generation. It is available until old generations are deleted.

## Test

```sh
nix build .#checks.<system>.site -L
```

The `site` VM test covers loading supautils from the site profile, the `$libdir` fallthrough, and `activate`.
