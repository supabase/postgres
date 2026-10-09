# Debug symbols

`postgres-env-*` does not carry debug symbols. Download them on the instance when you need them.

## Download

```bash
sudo /var/lib/postgresql/.nix-profile/bin/realise-postgres-debug
```

This fetches `postgres-env-<version>-debug` from the binary cache and installs it into the profile `/nix/var/nix/profiles/postgres-debug`. The debug env always matches the installed binaries, because it is built from the same derivations.

## Use with gdb

```bash
gdb -ex 'set debug-file-directory /nix/var/nix/profiles/postgres-debug/lib/debug' \
    -ex 'file /var/lib/postgresql/.nix-profile/bin/postgres' \
    -ex 'core-file <core>'
```

gdb finds the `.debug` files by build-id under `lib/debug/.build-id`.

## Source

The 15 and 17 debug envs have symbols only. The orioledb debug env also has the PostgreSQL source tree. Point gdb at it with `set substitute-path <comp_dir> /nix/var/nix/profiles/postgres-debug`.

## Remove

```bash
sudo /var/lib/postgresql/.nix-profile/bin/cleanup-postgres-debug
```

This removes the profile and all its generations. It does not collect garbage. Run `nix-collect-garbage` to free the space.

## Build

```bash
nix build .#postgres-env-17-debug
```
