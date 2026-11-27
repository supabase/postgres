# Site profile

The `site-env-15`, `site-env-17`, and `site-env-orioledb-17` package sets are deployed to `/nix/var/nix/profiles/site`. They hold supautils, `activate`, and `site-nix-gc`.

## Publish

`ami-release-nix.yml` uploads each store path as a string to the shared artifacts bucket, which is private, in the object `nix-catalog/<sha>/<system>/site-env-<major>`. Release branches also upload the git sha as a string to `nix-catalog/latest/<system>/site-env-<major>`. The AMI bake installs the store path passed in as `site_env_path` and runs `activate`.

## Update

```sh
nix-env --profile /nix/var/nix/profiles/site --set <store path>
/nix/var/nix/profiles/site/bin/activate
```

`--set` downloads the closure from the binary cache if it is missing. It then creates the generation link `site-<N>-link` to the store path and repoints the `site` symlink at that link. If it fails, `nix-env` exits with 1 and the profile is unchanged. This holds when the path can't be fetched, isn't a store path, or the profile directory isn't writable.

`activate` runs after the switch. It prints the library settings configured in `postgresql.conf`, and is idempotent. If it fails, the new generation stays active. Run `activate` again, or roll back.

New sessions load supautils from the new profile. Open sessions keep the copy they loaded until they reconnect. Postgres does not restart. A restart applies the change to every session at once. The same holds after a rollback.

`site-nix-gc` keeps the current generation and one older one for the site, postgres, and default profiles. It then runs `nix-store --gc` to completion. With systemd it runs in a throttled transient unit. Without systemd it runs under `nice` and `ionice`.

## Roll back

```sh
nix-env --profile /nix/var/nix/profiles/site --rollback
/nix/var/nix/profiles/site/bin/activate
```

Rollback switches to the previous generation. `activate` then runs from that generation and makes the machine match it. There is no separate rollback script.

`site-nix-gc` keeps the current generation and one older one. To go further back, install an older version by path.

## Install any version by path

```sh
nix-env --profile /nix/var/nix/profiles/site --set <older store path>
/nix/var/nix/profiles/site/bin/activate
```

This is the way to roll back past the one kept generation. It is the same as an update with an older path.

## `activate` safety

`activate` must be idempotent, and the previous generation's `activate` must be able to converge the machine back. Safety shall be ensured by comparing snapshots in tests before and after an update and a rollback.

## Test

```sh
nix build .#checks.<system>.site -L
```

The `site` VM test covers loading supautils from the site profile, the `$libdir` fallthrough, and `activate`.
