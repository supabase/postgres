# 01 &mdash; Using supabase nix

Let's clone this repo:

```bash
git clone https://github.com/supabase/postgres $HOME/supabase-postgres
cd $HOME/supabase-postgres
```

## Hashes for everyone

But how do we build stuff within it? With `nix build`, of course! For example,
the following command will, when completed, create a symlink named `result` that
points to a path which contains an entire PostgreSQL 15 installation &mdash;
extensions and all:

```
nix build .#psql_15/bin
```

```
$ readlink result
/nix/store/ybf48481x033649mgdzk5dyaqv9dppzx-postgresql-and-plugins-15.3
```

```
$ ls result
bin  include  lib  share
```

```
$ ll result/bin/
total 9928
dr-xr-xr-x 2 root root    4096 Dec 31  1969 ./
dr-xr-xr-x 5 root root    4096 Dec 31  1969 ../
lrwxrwxrwx 1 root root      79 Dec 31  1969 .initdb-wrapped -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/.initdb-wrapped*
-r-xr-xr-x 1 root root 9829624 Dec 31  1969 .postgres-wrapped*
lrwxrwxrwx 1 root root      73 Dec 31  1969 clusterdb -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/clusterdb*
lrwxrwxrwx 1 root root      72 Dec 31  1969 createdb -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/createdb*
lrwxrwxrwx 1 root root      74 Dec 31  1969 createuser -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/createuser*
lrwxrwxrwx 1 root root      70 Dec 31  1969 dropdb -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/dropdb*
lrwxrwxrwx 1 root root      72 Dec 31  1969 dropuser -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/dropuser*
lrwxrwxrwx 1 root root      68 Dec 31  1969 ecpg -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/ecpg*
lrwxrwxrwx 1 root root      70 Dec 31  1969 initdb -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/initdb*
lrwxrwxrwx 1 root root      72 Dec 31  1969 oid2name -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/oid2name*
lrwxrwxrwx 1 root root      74 Dec 31  1969 pg_amcheck -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_amcheck*
lrwxrwxrwx 1 root root      81 Dec 31  1969 pg_archivecleanup -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_archivecleanup*
lrwxrwxrwx 1 root root      77 Dec 31  1969 pg_basebackup -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_basebackup*
lrwxrwxrwx 1 root root      76 Dec 31  1969 pg_checksums -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_checksums*
-r-xr-xr-x 1 root root   53432 Dec 31  1969 pg_config*
lrwxrwxrwx 1 root root      78 Dec 31  1969 pg_controldata -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_controldata*
-r-xr-xr-x 1 root root   82712 Dec 31  1969 pg_ctl*
lrwxrwxrwx 1 root root      71 Dec 31  1969 pg_dump -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_dump*
lrwxrwxrwx 1 root root      74 Dec 31  1969 pg_dumpall -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_dumpall*
lrwxrwxrwx 1 root root      74 Dec 31  1969 pg_isready -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_isready*
lrwxrwxrwx 1 root root      77 Dec 31  1969 pg_receivewal -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_receivewal*
lrwxrwxrwx 1 root root      78 Dec 31  1969 pg_recvlogical -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_recvlogical*
lrwxrwxrwx 1 root root      73 Dec 31  1969 pg_repack -> /nix/store/bi9i5ns4cqxk235qz3srs9p4x1qfxfna-pg_repack-1.4.8/bin/pg_repack*
lrwxrwxrwx 1 root root      75 Dec 31  1969 pg_resetwal -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_resetwal*
lrwxrwxrwx 1 root root      74 Dec 31  1969 pg_restore -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_restore*
lrwxrwxrwx 1 root root      73 Dec 31  1969 pg_rewind -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_rewind*
lrwxrwxrwx 1 root root      77 Dec 31  1969 pg_test_fsync -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_test_fsync*
lrwxrwxrwx 1 root root      78 Dec 31  1969 pg_test_timing -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_test_timing*
lrwxrwxrwx 1 root root      74 Dec 31  1969 pg_upgrade -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_upgrade*
lrwxrwxrwx 1 root root      79 Dec 31  1969 pg_verifybackup -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_verifybackup*
lrwxrwxrwx 1 root root      74 Dec 31  1969 pg_waldump -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pg_waldump*
lrwxrwxrwx 1 root root      71 Dec 31  1969 pgbench -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/pgbench*
lrwxrwxrwx 1 root root      71 Dec 31  1969 pgsql2shp -> /nix/store/4wwzd3c136g6j7aqva2gyiqgwy784qjv-postgis-3.3.3/bin/pgsql2shp*
lrwxrwxrwx 1 root root      77 Dec 31  1969 pgsql2shp-3.3.3 -> /nix/store/4wwzd3c136g6j7aqva2gyiqgwy784qjv-postgis-3.3.3/bin/pgsql2shp-3.3.3*
lrwxrwxrwx 1 root root      75 Dec 31  1969 pgtopo_export -> /nix/store/4wwzd3c136g6j7aqva2gyiqgwy784qjv-postgis-3.3.3/bin/pgtopo_export*
lrwxrwxrwx 1 root root      81 Dec 31  1969 pgtopo_export-3.3.3 -> /nix/store/4wwzd3c136g6j7aqva2gyiqgwy784qjv-postgis-3.3.3/bin/pgtopo_export-3.3.3*
lrwxrwxrwx 1 root root      75 Dec 31  1969 pgtopo_import -> /nix/store/4wwzd3c136g6j7aqva2gyiqgwy784qjv-postgis-3.3.3/bin/pgtopo_import*
lrwxrwxrwx 1 root root      81 Dec 31  1969 pgtopo_import-3.3.3 -> /nix/store/4wwzd3c136g6j7aqva2gyiqgwy784qjv-postgis-3.3.3/bin/pgtopo_import-3.3.3*
-r-xr-xr-x 1 root root     286 Dec 31  1969 postgres*
lrwxrwxrwx 1 root root      74 Dec 31  1969 postmaster -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/postmaster*
lrwxrwxrwx 1 root root      68 Dec 31  1969 psql -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/psql*
lrwxrwxrwx 1 root root      74 Dec 31  1969 raster2pgsql -> /nix/store/4wwzd3c136g6j7aqva2gyiqgwy784qjv-postgis-3.3.3/bin/raster2pgsql*
lrwxrwxrwx 1 root root      80 Dec 31  1969 raster2pgsql-3.3.3 -> /nix/store/4wwzd3c136g6j7aqva2gyiqgwy784qjv-postgis-3.3.3/bin/raster2pgsql-3.3.3*
lrwxrwxrwx 1 root root      73 Dec 31  1969 reindexdb -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/reindexdb*
lrwxrwxrwx 1 root root      71 Dec 31  1969 shp2pgsql -> /nix/store/4wwzd3c136g6j7aqva2gyiqgwy784qjv-postgis-3.3.3/bin/shp2pgsql*
lrwxrwxrwx 1 root root      77 Dec 31  1969 shp2pgsql-3.3.3 -> /nix/store/4wwzd3c136g6j7aqva2gyiqgwy784qjv-postgis-3.3.3/bin/shp2pgsql-3.3.3*
lrwxrwxrwx 1 root root      72 Dec 31  1969 vacuumdb -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/vacuumdb*
lrwxrwxrwx 1 root root      72 Dec 31  1969 vacuumlo -> /nix/store/kdjdxnyhpwpvb11da8s99ylqilspcmzl-postgresql-15.3/bin/vacuumlo*
```

As we can see, these files all point to paths under `/nix/store`. We're actually
looking at a "farm" of symlinks to various paths, but collectively they form an
entire installation directory we can reuse as much as we want.

The path
`/nix/store/ybf48481x033649mgdzk5dyaqv9dppzx-postgresql-and-plugins-15.3`
ultimately is a cryptographically hashed, unique name for our installation of
PostgreSQL with those plugins. This hash includes _everything_ used to build it,
so even a single change anywhere to any extension or version would result in a
_new_ hash.

The ability to refer to a piece of data by its hash, by some notion of
_content_, is a very powerful primitive, as we'll see later.

## Build a different version: v16

What if we wanted PostgreSQL 16 and plugins? Just replace `_15` with `_16`:

```
nix build .#psql_16/bin
```

You're done:

```
$ readlink result
/nix/store/p7ziflx0000s28bfb213jsghrczknkc4-postgresql-and-plugins-14.8
```


## Using `nix develop`


`nix develop .` will just drop you in a subshell with
tools you need _ready to go instantly_. That's all you need to do! And once that
shell goes away, nix installed tools will be removed from your `$PATH` as well.

There's an even easier way to do this
[that is completely transparent to you, as well](./use-direnv.md).
