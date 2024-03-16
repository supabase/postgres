## Running the server

If you want to run a postgres server, just do this from the root of the
repository:

```
nix run .#start-server 14
```

Replace the `14` with a `15`, and you'll be using a different version. Optionally you can specify a second argument for the port.

You likely have a running postgres, so to not cause a conflict, this uses port 5435 by default.

Actually, you don't even need the repository. You can do this from arbitrary
directories, if the left-hand side of the hash character (`.` in this case) is a
valid "flake reference":

```
# from any arbitrary directory
nix run github:supabase/nix-postgres#start-server 14
```

### Arbitrary versions at arbitrary git revisions

Let's say you want to use a PostgreSQL build from a specific version of the
repository. You can change the syntax of the above to use _any_ version of the
repository, at any time, by adding the commit hash after the repository name:

```
# use postgresql 15 build at commit a9989d4800dd6038827afed27456f19ba4b2ae0a
nix run github:supabase/nix-postgres/a9989d4800dd6038827afed27456f19ba4b2ae0a#start-server 15
```

## Running the client

All of the same rules apply, but try using `start-client` on the right-hand side
of the hash character, instead. For example:

```
nix run github:supabase/nix-postgres#start-server 14 &
sleep 5
nix run github:supabase/nix-postgres#start-client 15
```

## Running a server replica

To start a replica you can use the `start-postgres-replica` command.

- first argument: the master version
- second argument: the master port
- third argument: the replica server port

First start a server and a couple of replicas:

```
$ start-postgres-server 15 5435

$ start-postgres-replica 15 5439

$ start-postgres-replica 15 5440
```

Now check the master server:

```
$ start-postgres-client 15 5435
```

```sql
SELECT client_addr, state
FROM pg_stat_replication;
 client_addr |   state
-------------+-----------
 ::1         | streaming
 ::1         | streaming
(2 rows)

create table items as select x::int from generate_series(1,100) x;
```

And a replica:

```
$ start-postgres-client 15 5439
```

```sql
select count(*) from items;
 count
-------
   100
(1 row)
```
