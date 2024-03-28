Extensions are managed in two places: upstream, and this repository. Therefore
there are two update strategies available.

## Updating extensions in this repository

Assuming that you run `nix develop` to get a development shell, there is a tool
named `nix-update` that is available:

```
austin@GANON:~/work/nix-postgres$ which nix-update
/nix/store/2jyq6h0ln3f5vlgz2had80l2crdkjmdy-nix-update-0.19.2/bin/nix-update
```

Run something like this to update the extension `pg_foobar`:

```bash
nix-update --flake psql_15/exts/pg_foobar
git commit -asm "pg_foobar: update to latest release"
```

It doesn't matter if you use `psql_15` or `psql_16` here, because `nix-update`
will look at the _file_ that extension is defined in, in order to update the
source code.

## Updating extensions upstream

You can use the same tool, `nix-update`, to do this. If you're sitting in the
root of the nixpkgs repository, try this:

```
nix run nixpkgs#nix-update -- postgresqlPackages.pg_foobar
git commit -asm "pg_foobar: update to latest release"
```

Because the tool may not be in your shell by default, we use `nix run` to run it
for us.

The full list of available names to substitute for `pg_foobar` is available in
the file
[pkgs/servers/sql/postgresql/packages.nix](https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/sql/postgresql/packages.nix)

### Updating the Nixpkgs snapshot

Now that your change is merged upstream, you need to update the version of
`nixpkgs` used in this repository:

- Check the `nixpkgs-unstable` branch:
  https://github.com/nixos/nixpkgs/tree/nixpkgs-unstable
- Wait until your commit is fast-forwarded and part of that branch
- Run `nix flake update`

## Release tags versus latest trunk

By default, `nix-update` will update an expression to the latest tagged release.
No extra arguments are necessary. You can specify an exact release tag using the
`--version=<xyz>` flag. Using the syntax `--version=branch` means "update to the
latest version on the default branch."

<!-- ## Example PRs

- https://github.com/supabase/nix-postgres/pull/9 updates `pg_net` to the latest
  release
- https://github.com/supabase/nix-postgres/pull/7 updates `pg_hashids` to the
  latest `trunk` tip
-->
## Other notes

See issue [#5](https://github.com/supabase/nix-postgres/issues/5) for more
information about extension management.
