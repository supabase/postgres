# Supabase Postgres 

Unmodified Postgres with some useful plugins. Our goal with this repo is not to modify Postgres, but to provide some of the most common extensions with a one-click install.

## Features

- ✅ Postgres 12
- ✅ Ubuntu 18.04 (Bionic) 
- ✅ [pg-contrib-12](https://www.postgresql.org/docs/12/contrib.html). Because everyone should enable `pg_stat_statements`.
- ⏳ `readonly` role. A readonly role set up by default for the public schema.
- ✅ [wal_level]((https://www.postgresql.org/docs/current/runtime-config-wal.html)) = logical. Ready for replication.
- ✅ [PostGIS](https://postgis.net/). Postgres' most popular extension - support for geographic objects.
- ✅ [pgTAP](https://pgtap.org/). Unit Testing for Postgres
- ⏳ [plv8](https://github.com/plv8/plv8) - [coming soon](https://github.com/supabase/postgres/issues/5#issuecomment-621129147). Write in Javascript functions in Postgres.
- ⏳ PL/python - [coming soon](https://github.com/supabase/postgres/issues/5#issuecomment-621129797). Write in Python functions in Postgres.

## Install

See all installation instructions in the [repo wiki](https://github.com/supabase/postgres/wiki).

[![Docker](https://github.com/supabase/postgres/blob/master/docs/img/docker.png)](https://github.com/supabase/postgres/wiki/Docker)
[![Digital Ocean](https://github.com/supabase/postgres/blob/master/docs/img/digital-ocean.png)](https://github.com/supabase/postgres/wiki/Digital-Ocean)
[![AWS](https://github.com/supabase/postgres/blob/master/docs/img/aws.png)](https://github.com/supabase/postgres/wiki/AWS-EC2)

## Motivation

After talking to a lot of people, we've found that most techies believe Postgres is the best (operational) database but they *still* choose other databases. This is overwhelmingly because "the other one was quicker/easier". Our goal is to make it quick and simple to get started with Postgres, so that we never hear that excuse again. 

This is also the same build we offer for [Supabase](https://supabase.io), and everything we do is opensource.

## Roadmap

- [Support for more images](https://github.com/supabase/postgres/issues/4)
- [Vote for more plugins/extensions](https://github.com/supabase/postgres/issues/5)
- Open a github issue if you have a feature request

## License

[The PostgreSQL License](https://opensource.org/licenses/postgresql). We realize that licensing is tricky since we are bundling all the various plugins. If we have infringed on any license, let us know and we will make the necessary changes (or remove that extension from this repo).
