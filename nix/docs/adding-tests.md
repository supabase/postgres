There are basically two types of tests you can add:

- pgTAP based tests, and
- Migration tests.

In both cases, a number of extensions may be installed into the database for
use; you can see those in both [postgresql.conf.in](../tests/postgresql.conf.in)
and [prime.sql](../tests/prime.sql) (extensions may be enabled in either place.)

## pgTAP tests

These are super easy: simply add `.sql` files to the
[tests/smoke](./../tests/smoke/) directory, then:

```
nix flake check -L
```

(`-L` prints logs to stderrr, for more details see `man nix`)

These files are run using `pg_prove`; they pretty much behave exactly like how
you expect; you can read
[the pgTAP documentation](https://pgtap.org/documentation.html) for more.

For a good example of a pgTAP test as a pull request, check out
[pull request #4](https://github.com/supabase/nix-postgres/pull/4/files).

## Re-running tests

`nix flake check` gets its results cached, so if you do it again the tests won't rerun. If you change a file then it will run again.

<!-- If you want to force rerun without modifying a file, you can do:

```
nix build .#checks.x86_64-linux.psql_15 --rebuild
nix build .#checks.x86_64-linux.psql_16 --rebuild
```
-->

Limitation: currently there's no way to rerun all the tests, so you have to specify the check attribute.

To get the correct attribute (`#checks.x86_64-linux.psql_15` above), you can do `nix flake show`. This will show a tree with all the output attributes.

## Migration tests

> **NOTE**: Currently, migration tests _do not happen in CI_. They can only be
> run manually.

Migration tests are pretty simple in the sense they follow a very simple
principle:

- You put data in the database
- Run the migration procedure
- It should probably not fail

Step 1 and 2 are easy, and for various reasons (e.g. mistakes from upstream
extension authors), step 3 isn't guaranteed, so that's what the whole idea is
designed to test.

To add data into the database, modify the
[data.sql](../nix/tests/migrations/data.sql) script and add whatever you want into
it. This script gets loaded into the old version of the database at startup, and
it's expected that the new version of the database can handle it.

To run the `migration-test` tool, check out the documentation on
[migration-tests](./migration-tests.md).
