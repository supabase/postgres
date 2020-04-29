# Supabase Postgres 

Unmodified Postgres with some useful plugins. Our goal with this repo is not to modify Postgres, but to provide some of the most common extensions with a one-click install.

## Features

✅ Postgres 12
✅ `wal_level` = `logical`
✅ `pgcrypto` 
✅ `pg_stat_statements` 
✅ `postgis`
✅ `pgTAP` 

## Install

See all installation instructions in the [repo wiki](https://github.com/supabase/postgres/wiki).

[Docker](https://github.com/supabase/postgres/wiki/Docker) | [EC2](https://github.com/supabase/postgres/wiki/AWS-EC2) | [Digital Ocean](https://github.com/supabase/postgres/wiki/Digital-Ocean)

## Motivation

After talking to a lot of people, we've found that most techies believe Postgres is the best (operational) database but they *still* choose other databases. This is overwhelmingly because "the other one was quicker/easier". Our goal is to make it quick and simple to get started with Postgres, so that we never hear that excuse again. 

## Roadmap

- [Support for more images](https://github.com/supabase/postgres/issues/4)
- [Vote for more plugins/extensions](https://github.com/supabase/postgres/issues/5)
- Open a github issue if you have a feature request

## License

[The PostgreSQL License](https://opensource.org/licenses/postgresql). We realize that licensing is tricky since we are bundling all the various plugins. If we have infringed on any license, let us know and we will make the necessary changes (or remove that extension from this repo).
