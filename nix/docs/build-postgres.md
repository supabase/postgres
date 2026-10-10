# 01 &mdash; Using supabase nix

Let's clone this repo:

```bash
git clone https://github.com/supabase/postgres $HOME/supabase-postgres
cd $HOME/supabase-postgres
```

## Hashes for everyone

Build with [`nix build`](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-build.html). For example,
the following command will, when completed, create a symlink named `result` that
points to a path which contains an entire PostgreSQL 15 installation &mdash;
extensions and all:

```
nix build .#psql_15.bin
```

```
$ readlink result
/nix/store/<hash>-postgresql-and-plugins-15.19
```

```
$ ls result
bin  include  lib  share
```

The files in `result/bin` point to paths under `/nix/store`. The `result` directory is a farm of symlinks to various paths.
Collectively they form an entire installation directory we can reuse as much as we want.

The path
`/nix/store/<hash>-postgresql-and-plugins-15.19`
ultimately is a cryptographically hashed, unique name for our installation of
PostgreSQL with those plugins. This hash includes _everything_ used to build it,
so even a single change anywhere to any extension or version would result in a
_new_ hash.

The ability to refer to a piece of data by its hash, by some notion of
_content_, is a very powerful primitive, as we'll see later.

## Build a different version: v17

What if we wanted PostgreSQL 17 and plugins? Just replace `_15` with `_17`:

```
nix build .#psql_17.bin
```

You're done:

```
$ readlink result
/nix/store/<hash>-postgresql-and-plugins-17.11
```


## Using `nix develop`

[`nix develop .`](https://nix.dev/manual/nix/stable/command-ref/new-cli/nix3-develop.html) drops you in a subshell with the tools you need.

To load the shell automatically, use [direnv](https://direnv.net) with [nix-direnv](https://github.com/nix-community/nix-direnv):

```bash
echo "source_env .envrc.recommended" >> .envrc
direnv allow
```
