# Site profile

The `site-env-15`, `site-env-17`, and `site-env-orioledb-17` package sets are deployed to `/nix/var/nix/profiles/site`. They hold supautils, and `activate`.

`dynamic_library_path` in `postgresql.conf` includes `/nix/var/nix/profiles/site/lib/postgresql` first, then `$libdir`. supautils also remains in `$libdir`, pending cleanup.

## Publish

`ami-release-nix.yml` uploads each store path as a string to the shared artifacts bucket, in the object `nix-catalog/<sha>/<system>/site-env-<major>`. Release branches also upload the git sha as a string to `nix-catalog/latest/<system>/site-env-<major>`. The AMI bake installs the store path passed in as `site_env_path` and runs `activate`.

## Update

```sh
nix-env --profile /nix/var/nix/profiles/site --set <store path>
/nix/var/nix/profiles/site/bin/activate
```

`--set` downloads the closure from the binary cache if it is missing. It then creates the generation link `site-<N>-link` to the store path and repoints the `site` symlink at that link. If it fails, `nix-env` exits with 1 and the profile is unchanged. This holds when the path can't be fetched, isn't a store path, or the profile directory isn't writable.

`activate` runs after the switch. It prints the library settings configured in `postgresql.conf`, and is idempotent. If it fails, the new generation stays active. Run `activate` again, or roll back.

## Roll back

```sh
nix-env --profile /nix/var/nix/profiles/site --rollback
/nix/var/nix/profiles/site/bin/activate
```

Rollback switches to the previous generation. `activate` then runs from that generation and makes the machine match it. There is no separate rollback script.

To go further back than the previous generation, install an older version by path.

New sessions load supautils from the rolled-back profile. Open sessions keep the copy they loaded until they reconnect. Postgres does not restart. A restart applies the change to every session at once.

## Install any version by path

```sh
nix-env --profile /nix/var/nix/profiles/site --set <older store path>
/nix/var/nix/profiles/site/bin/activate
```

This is the way to roll back past the one kept generation. It is the same as an update with an older path.

## What `activate` may do

`activate` must be idempotent, and the previous generation's `activate` must be able to converge the machine back. A step is allowed when:

1. It links through the profile path, such as `/nix/var/nix/profiles/site/lib/…`. The link follows the profile and needs no undo.
2. It is harmless when it dangles after a rollback to a profile that lacks the target.
3. Otherwise it has its own undo, decided case by case. Treat any such step as a flag in review.

The roundtrip test compares a manifest before the update and after the rollback. A step that breaks these rules fails it.

## Test

```sh
nix build .#checks.<system>.site -L
```

The `site` VM test covers loading supautils from the site profile, the `$libdir` fallthrough, and `activate`.
