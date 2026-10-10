# Debug symbols

`postgres-env-*` does not carry debug symbols. Download them on the instance when you need them.

## Download

```bash
/var/lib/postgresql/.nix-profile/bin/realise-postgres-debug
```

This fetches `postgres-env-<version>-debug` from the binary cache and prints its store path. The debug env always matches the installed binaries, because it is built from the same derivations. It is not pinned, so garbage collection removes it.

## Use with gdb

```bash
DEBUG=$(/var/lib/postgresql/.nix-profile/bin/realise-postgres-debug)
gdb -ex "set debug-file-directory $DEBUG/lib/debug" \
    -ex 'file /var/lib/postgresql/.nix-profile/bin/postgres' \
    -ex 'core-file <core>'
```

gdb finds the `.debug` files by build-id under `lib/debug/.build-id`.

## Source

The 15 and 17 debug envs have symbols only. The orioledb debug env also has the PostgreSQL source tree. Point gdb at it with `set substitute-path <comp_dir> $DEBUG`.

## Build

```bash
nix build .#postgres-env-17-debug
```
