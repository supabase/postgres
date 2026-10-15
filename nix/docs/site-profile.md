# Site profile

The `site-env-15`, `site-env-17`, and `site-env-orioledb-17` package sets are deployed to `/nix/var/nix/profiles/site`. They hold supautils, `activate`, and `site-nix-gc`.

`dynamic_library_path` in `postgresql.conf` includes `/nix/var/nix/profiles/site/lib/postgresql` first, then `$libdir`. supautils also remains in `$libdir`, pending cleanup.

## Publish

`ami-release-nix.yml` uploads each store path as a string to the public artifacts bucket, in the object `nix-catalog/<sha>-site-env-<major>-<system>`. Release branches also upload the git sha as a string to `latest-site-env-<major>-<system>.sha`. The AMI bake installs the store path passed in as `site_env_path` and runs `activate`.

## Update

```sh
nix-env --profile /nix/var/nix/profiles/site --set <store path>
/nix/var/nix/profiles/site/bin/activate
```

`--set` downloads the closure from the binary cache if it is missing. It then creates the generation link `site-<N>-link` to the store path and repoints the `site` symlink at that link. If the download fails, `nix-env` exits non-zero and the profile is unchanged.

`activate` runs after the switch. It sets up supautils, and gatekeeper where present, idempotently. If it fails, the new generation stays active. Run `activate` again, or roll back.

`site-nix-gc` keeps the current generation and one older one for the site, postgres, and default profiles. It then runs `nix-store --gc` to completion. With systemd it runs in a throttled transient unit. Without systemd it runs under `nice` and `ionice`.

## Roll back

```sh
nix-env --profile /nix/var/nix/profiles/site --rollback
```

Rollback switches to the previous generation. `site-nix-gc` keeps one.

## Test

```sh
nix build .#checks.<system>.site -L
```

The `site` VM test covers loading supautils from the site profile, the `$libdir` fallthrough, and `activate`.
