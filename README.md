# Postgres + goodies

Unmodified Postgres with some useful plugins. Our goal with this repo is not to modify Postgres, but to provide some of the most common extensions with a one-click install.

## Features

- ✅ Postgres [12](https://www.postgresql.org/about/news/1976/). Includes [generated columns](https://www.postgresql.org/docs/12/ddl-generated-columns.html) and [JSON path](https://www.postgresql.org/docs/12/functions-json.html#FUNCTIONS-SQLJSON-PATH) support.
- ✅ Ubuntu 18.04 (Bionic). 
- ✅ [pg-contrib-12](https://www.postgresql.org/docs/12/contrib.html). Because everyone should enable `pg_stat_statements`.
- ✅ [wal_level](https://www.postgresql.org/docs/current/runtime-config-wal.html) = logical and [max_replication_slots](https://www.postgresql.org/docs/current/runtime-config-replication.html) = 5. Ready for replication.
- ✅ [PostGIS](https://postgis.net/). Postgres' most popular extension - support for geographic objects.
- ✅ [pgTAP](https://pgtap.org/). Unit Testing for Postgres.
- ✅ [pgAudit](https://www.pgaudit.org/). Generate highly compliant audit logs.
- ✅ [pgjwt](https://github.com/michelp/pgjwt). Generate JSON Web Tokens (JWT) in Postgres.
- ✅ [pgsql-http](https://github.com/pramsey/pgsql-http). HTTP client for Postgres.
- ✅ [plpgsql_check](https://github.com/okbob/plpgsql_check). Linter tool for PL/pgSQL.
- ✅ [plv8](https://github.com/plv8/plv8). Write in Javascript functions in Postgres.
- ✅ [plpython3u](https://www.postgresql.org/docs/current/plpython-python23.html). Python3 enabled by default. Write in Python functions in Postgres.
- ✅ [PL/Java](https://github.com/tada/pljaval). Write in Java functions in Postgres.

## Install

See all installation instructions in the [repo wiki](https://github.com/supabase/postgres/wiki).

[![Docker](https://github.com/supabase/postgres/blob/master/docs/img/docker.png)](https://github.com/supabase/postgres/wiki/Docker)
[![Digital Ocean](https://github.com/supabase/postgres/blob/master/docs/img/digital-ocean.png)](https://github.com/supabase/postgres/wiki/Digital-Ocean)
[![AWS](https://github.com/supabase/postgres/blob/master/docs/img/aws.png)](https://github.com/supabase/postgres/wiki/AWS-EC2)

## Motivation

After talking to a lot of techies, we've found that most believe Postgres is the best (operational) database but they *still* choose other databases. This is overwhelmingly because "the other one was quicker/easier". Our goal is to make it fast and simple to get started with Postgres, so that we never hear that excuse again. 

Our secondary goal is to show off a few of Postgres' most exciting features. This is to convince new developers to choose it over other database (a decision we hope they'll appreciate once they start scaling).

Finally, this is the same build we offer at [Supabase](https://supabase.io), and everything we do is opensource. This repo makes it easy to *install* Postgres, Supabase makes it easy to *use* Postgres.

## Roadmap

- [Support for more images](https://github.com/supabase/postgres/issues/4)
- [Vote for more plugins/extensions](https://github.com/supabase/postgres/issues/5)
- Open a github issue if you have a feature request

## License

[The PostgreSQL License](https://opensource.org/licenses/postgresql). We realize that licensing is tricky since we are bundling all the various plugins. If we have infringed on any license, let us know and we will make the necessary changes (or remove that extension from this repo).

## Sponsors

We are building the features of Firebase using enterprise-grade, open source products. We support existing communities wherever possible, and if the products don’t exist we build them and open source them ourselves. Thanks to these sponsors who are making the OSS ecosystem better for everyone.

[![Worklife VC](https://user-images.githubusercontent.com/10214025/90451355-34d71200-e11e-11ea-81f9-1592fd1e9146.png)](https://www.worklife.vc)
[![New Sponsor](https://user-images.githubusercontent.com/10214025/90518111-e74bbb00-e198-11ea-8f88-c9e3c1aa4b5b.png)](https://github.com/sponsors/supabase)

