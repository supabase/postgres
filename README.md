# Postgres + goodies

Unmodified Postgres with some useful plugins. Our goal with this repo is not to modify Postgres, but to provide some of the most common extensions with a one-click install.

## Primary Features
- ✅ Postgres [postgresql-15.8](https://www.postgresql.org/docs/15/index.html)
- ✅ Postgres [orioledb-postgresql-17_5](https://github.com/orioledb/orioledb)
- ✅ Ubuntu 20.04 (Focal Fossa).
- ✅ [wal_level](https://www.postgresql.org/docs/current/runtime-config-wal.html) = logical and [max_replication_slots](https://www.postgresql.org/docs/current/runtime-config-replication.html) = 5. Ready for replication.
- ✅ [Large Systems Extensions](https://github.com/aws/aws-graviton-getting-started#building-for-graviton-and-graviton2). Enabled for ARM images.
## Extensions 

### PostgreSQL 15 Extensions
| Extension | Version | Description |
| ------------- | :-------------: | ------------- |
| [hypopg](https://github.com/HypoPG/hypopg/archive/refs/tags/1.4.1.tar.gz) | [1.4.1](https://github.com/HypoPG/hypopg/archive/refs/tags/1.4.1.tar.gz) | Hypothetical Indexes for PostgreSQL |
| [index_advisor](https://github.com/olirice/index_advisor/archive/v0.2.0.tar.gz) | [0.2.0](https://github.com/olirice/index_advisor/archive/v0.2.0.tar.gz) | Recommend indexes to improve query performance in PostgreSQL |
| [pg-safeupdate](https://github.com/eradman/pg-safeupdate/archive/1.4.tar.gz) | [1.4](https://github.com/eradman/pg-safeupdate/archive/1.4.tar.gz) | A simple extension to PostgreSQL that requires criteria for UPDATE and DELETE |
| [pg_backtrace](https://github.com/pashkinelfe/pg_backtrace/archive/d100bac815a7365e199263f5b3741baf71b14c70.tar.gz) | [1.1](https://github.com/pashkinelfe/pg_backtrace/archive/d100bac815a7365e199263f5b3741baf71b14c70.tar.gz) | Updated fork of pg_backtrace |
| [pg_cron](https://github.com/citusdata/pg_cron/archive/v1.6.4.tar.gz) | [1.6.4](https://github.com/citusdata/pg_cron/archive/v1.6.4.tar.gz) | Run Cron jobs through PostgreSQL |
| [pg_graphql](https://github.com/supabase/pg_graphql/archive/v1.5.9.tar.gz) | [1.5.9](https://github.com/supabase/pg_graphql/archive/v1.5.9.tar.gz) | GraphQL support for PostreSQL |
| [pg_hashids](https://github.com/iCyberon/pg_hashids/archive/cd0e1b31d52b394a0df64079406a14a4f7387cd6.tar.gz) | [cd0e1b31d52b394a0df64079406a14a4f7387cd6](https://github.com/iCyberon/pg_hashids/archive/cd0e1b31d52b394a0df64079406a14a4f7387cd6.tar.gz) | Generate short unique IDs in PostgreSQL |
| [pg_jsonschema](https://github.com/supabase/pg_jsonschema/archive/v0.3.3.tar.gz) | [0.3.3](https://github.com/supabase/pg_jsonschema/archive/v0.3.3.tar.gz) | JSON Schema Validation for PostgreSQL |
| [pg_net](https://github.com/supabase/pg_net/archive/refs/tags/v0.14.0.tar.gz) | [0.14.0](https://github.com/supabase/pg_net/archive/refs/tags/v0.14.0.tar.gz) | Async networking for Postgres |
| [pg_plan_filter](https://github.com/pgexperts/pg_plan_filter/archive/5081a7b5cb890876e67d8e7486b6a64c38c9a492.tar.gz) | [5081a7b5cb890876e67d8e7486b6a64c38c9a492](https://github.com/pgexperts/pg_plan_filter/archive/5081a7b5cb890876e67d8e7486b6a64c38c9a492.tar.gz) | Filter PostgreSQL statements by execution plans |
| [pg_repack](https://github.com/reorg/pg_repack/archive/ver_1.5.2.tar.gz) | [1.5.2](https://github.com/reorg/pg_repack/archive/ver_1.5.2.tar.gz) | Reorganize tables in PostgreSQL databases with minimal locks |
| [pg_stat_monitor](https://github.com/percona/pg_stat_monitor/archive/refs/tags/2.1.0.tar.gz) | [2.1.0](https://github.com/percona/pg_stat_monitor/archive/refs/tags/2.1.0.tar.gz) | Query Performance Monitoring Tool for PostgreSQL |
| [pg_tle](https://github.com/aws/pg_tle/archive/refs/tags/v1.4.0.tar.gz) | [1.4.0](https://github.com/aws/pg_tle/archive/refs/tags/v1.4.0.tar.gz) | Framework for 'Trusted Language Extensions' in PostgreSQL |
| [pgaudit](https://github.com/pgaudit/pgaudit/archive/1.7.0.tar.gz) | [1.7.0](https://github.com/pgaudit/pgaudit/archive/1.7.0.tar.gz) | Open Source PostgreSQL Audit Logging |
| [pgjwt](https://github.com/michelp/pgjwt/archive/9742dab1b2f297ad3811120db7b21451bca2d3c9.tar.gz) | [9742dab1b2f297ad3811120db7b21451bca2d3c9](https://github.com/michelp/pgjwt/archive/9742dab1b2f297ad3811120db7b21451bca2d3c9.tar.gz) | PostgreSQL implementation of JSON Web Tokens |
| [pgmq](https://github.com/tembo-io/pgmq/archive/v1.4.4.tar.gz) | [1.4.4](https://github.com/tembo-io/pgmq/archive/v1.4.4.tar.gz) | A lightweight message queue. Like AWS SQS and RSMQ but on Postgres. |
| [pgroonga](https://packages.groonga.org/source/pgroonga/pgroonga-3.2.5.tar.gz) | [3.2.5](https://packages.groonga.org/source/pgroonga/pgroonga-3.2.5.tar.gz) | A PostgreSQL extension to use Groonga as the index |
| [pgrouting](https://github.com/pgRouting/pgrouting/archive/v3.4.1.tar.gz) | [3.4.1](https://github.com/pgRouting/pgrouting/archive/v3.4.1.tar.gz) | A PostgreSQL/PostGIS extension that provides geospatial routing functionality |
| [pgsodium](https://github.com/michelp/pgsodium/archive/refs/tags/v3.1.8.tar.gz) | [3.1.8](https://github.com/michelp/pgsodium/archive/refs/tags/v3.1.8.tar.gz) | Modern cryptography for PostgreSQL |
| [pgsql-http](https://github.com/pramsey/pgsql-http/archive/refs/tags/v1.6.1.tar.gz) | [1.6.1](https://github.com/pramsey/pgsql-http/archive/refs/tags/v1.6.1.tar.gz) | HTTP client for Postgres |
| [pgtap](https://github.com/theory/pgtap/archive/v1.2.0.tar.gz) | [1.2.0](https://github.com/theory/pgtap/archive/v1.2.0.tar.gz) | A unit testing framework for PostgreSQL |
| [pgvector](https://github.com/pgvector/pgvector/archive/refs/tags/v0.8.0.tar.gz) | [0.8.0](https://github.com/pgvector/pgvector/archive/refs/tags/v0.8.0.tar.gz) | Open-source vector similarity search for Postgres |
| [plpgsql-check](https://github.com/okbob/plpgsql_check/archive/v2.7.11.tar.gz) | [2.7.11](https://github.com/okbob/plpgsql_check/archive/v2.7.11.tar.gz) | Linter tool for language PL/pgSQL |
| [plv8](https://github.com/plv8/plv8/archive/v3.1.10.tar.gz) | [3.1.10](https://github.com/plv8/plv8/archive/v3.1.10.tar.gz) | V8 Engine Javascript Procedural Language add-on for PostgreSQL |
| [postgis](https://download.osgeo.org/postgis/source/postgis-3.3.7.tar.gz) | [3.3.7](https://download.osgeo.org/postgis/source/postgis-3.3.7.tar.gz) | Geographic Objects for PostgreSQL |
| [rum](https://github.com/postgrespro/rum/archive/1.3.14.tar.gz) | [1.3.14](https://github.com/postgrespro/rum/archive/1.3.14.tar.gz) | Full text search index method for PostgreSQL |
| [supabase-wrappers](https://github.com/supabase/wrappers/archive/v0.4.4.tar.gz) | [0.4.4](https://github.com/supabase/wrappers/archive/v0.4.4.tar.gz) | Various Foreign Data Wrappers (FDWs) for PostreSQL |
| [supautils](https://github.com/supabase/supautils/archive/refs/tags/v2.6.0.tar.gz) | [2.6.0](https://github.com/supabase/supautils/archive/refs/tags/v2.6.0.tar.gz) | PostgreSQL extension for enhanced security |
| [timescaledb-apache](https://github.com/timescale/timescaledb/archive/2.16.1.tar.gz) | [2.16.1](https://github.com/timescale/timescaledb/archive/2.16.1.tar.gz) | Scales PostgreSQL for time-series data via automatic partitioning across time and space |
| [vault](https://github.com/supabase/vault/archive/refs/tags/v0.2.9.tar.gz) | [0.2.9](https://github.com/supabase/vault/archive/refs/tags/v0.2.9.tar.gz) | Store encrypted secrets in PostgreSQL |
| [wal2json](https://github.com/eulerto/wal2json/archive/wal2json_2_6.tar.gz) | [2_6](https://github.com/eulerto/wal2json/archive/wal2json_2_6.tar.gz) | PostgreSQL JSON output plugin for changeset extraction |

### PostgreSQL orioledb-17 Extensions
| Extension | Version | Description |
| ------------- | :-------------: | ------------- |
| [hypopg](https://github.com/HypoPG/hypopg/archive/refs/tags/1.4.1.tar.gz) | [1.4.1](https://github.com/HypoPG/hypopg/archive/refs/tags/1.4.1.tar.gz) | Hypothetical Indexes for PostgreSQL |
| [index_advisor](https://github.com/olirice/index_advisor/archive/v0.2.0.tar.gz) | [0.2.0](https://github.com/olirice/index_advisor/archive/v0.2.0.tar.gz) | Recommend indexes to improve query performance in PostgreSQL |
| [orioledb](https://github.com/orioledb/orioledb/archive/beta9.tar.gz) | [orioledb](https://github.com/orioledb/orioledb/archive/beta9.tar.gz) | orioledb |
| [pg-safeupdate](https://github.com/eradman/pg-safeupdate/archive/1.4.tar.gz) | [1.4](https://github.com/eradman/pg-safeupdate/archive/1.4.tar.gz) | A simple extension to PostgreSQL that requires criteria for UPDATE and DELETE |
| [pg_backtrace](https://github.com/pashkinelfe/pg_backtrace/archive/d100bac815a7365e199263f5b3741baf71b14c70.tar.gz) | [1.1](https://github.com/pashkinelfe/pg_backtrace/archive/d100bac815a7365e199263f5b3741baf71b14c70.tar.gz) | Updated fork of pg_backtrace |
| [pg_cron](https://github.com/citusdata/pg_cron/archive/v1.6.4.tar.gz) | [1.6.4](https://github.com/citusdata/pg_cron/archive/v1.6.4.tar.gz) | Run Cron jobs through PostgreSQL |
| [pg_graphql](https://github.com/supabase/pg_graphql/archive/v1.5.9.tar.gz) | [1.5.9](https://github.com/supabase/pg_graphql/archive/v1.5.9.tar.gz) | GraphQL support for PostreSQL |
| [pg_hashids](https://github.com/iCyberon/pg_hashids/archive/cd0e1b31d52b394a0df64079406a14a4f7387cd6.tar.gz) | [cd0e1b31d52b394a0df64079406a14a4f7387cd6](https://github.com/iCyberon/pg_hashids/archive/cd0e1b31d52b394a0df64079406a14a4f7387cd6.tar.gz) | Generate short unique IDs in PostgreSQL |
| [pg_jsonschema](https://github.com/supabase/pg_jsonschema/archive/v0.3.3.tar.gz) | [0.3.3](https://github.com/supabase/pg_jsonschema/archive/v0.3.3.tar.gz) | JSON Schema Validation for PostgreSQL |
| [pg_net](https://github.com/supabase/pg_net/archive/refs/tags/v0.14.0.tar.gz) | [0.14.0](https://github.com/supabase/pg_net/archive/refs/tags/v0.14.0.tar.gz) | Async networking for Postgres |
| [pg_plan_filter](https://github.com/pgexperts/pg_plan_filter/archive/5081a7b5cb890876e67d8e7486b6a64c38c9a492.tar.gz) | [5081a7b5cb890876e67d8e7486b6a64c38c9a492](https://github.com/pgexperts/pg_plan_filter/archive/5081a7b5cb890876e67d8e7486b6a64c38c9a492.tar.gz) | Filter PostgreSQL statements by execution plans |
| [pg_repack](https://github.com/reorg/pg_repack/archive/ver_1.5.2.tar.gz) | [1.5.2](https://github.com/reorg/pg_repack/archive/ver_1.5.2.tar.gz) | Reorganize tables in PostgreSQL databases with minimal locks |
| [pg_stat_monitor](https://github.com/percona/pg_stat_monitor/archive/refs/tags/2.1.0.tar.gz) | [2.1.0](https://github.com/percona/pg_stat_monitor/archive/refs/tags/2.1.0.tar.gz) | Query Performance Monitoring Tool for PostgreSQL |
| [pg_tle](https://github.com/aws/pg_tle/archive/refs/tags/v1.4.0.tar.gz) | [1.4.0](https://github.com/aws/pg_tle/archive/refs/tags/v1.4.0.tar.gz) | Framework for 'Trusted Language Extensions' in PostgreSQL |
| [pgaudit](https://github.com/pgaudit/pgaudit/archive/17.0.tar.gz) | [17.0](https://github.com/pgaudit/pgaudit/archive/17.0.tar.gz) | Open Source PostgreSQL Audit Logging |
| [pgjwt](https://github.com/michelp/pgjwt/archive/9742dab1b2f297ad3811120db7b21451bca2d3c9.tar.gz) | [9742dab1b2f297ad3811120db7b21451bca2d3c9](https://github.com/michelp/pgjwt/archive/9742dab1b2f297ad3811120db7b21451bca2d3c9.tar.gz) | PostgreSQL implementation of JSON Web Tokens |
| [pgmq](https://github.com/tembo-io/pgmq/archive/v1.4.4.tar.gz) | [1.4.4](https://github.com/tembo-io/pgmq/archive/v1.4.4.tar.gz) | A lightweight message queue. Like AWS SQS and RSMQ but on Postgres. |
| [pgroonga](https://packages.groonga.org/source/pgroonga/pgroonga-3.2.5.tar.gz) | [3.2.5](https://packages.groonga.org/source/pgroonga/pgroonga-3.2.5.tar.gz) | A PostgreSQL extension to use Groonga as the index |
| [pgrouting](https://github.com/pgRouting/pgrouting/archive/v3.4.1.tar.gz) | [3.4.1](https://github.com/pgRouting/pgrouting/archive/v3.4.1.tar.gz) | A PostgreSQL/PostGIS extension that provides geospatial routing functionality |
| [pgsodium](https://github.com/michelp/pgsodium/archive/refs/tags/v3.1.8.tar.gz) | [3.1.8](https://github.com/michelp/pgsodium/archive/refs/tags/v3.1.8.tar.gz) | Modern cryptography for PostgreSQL |
| [pgsql-http](https://github.com/pramsey/pgsql-http/archive/refs/tags/v1.6.1.tar.gz) | [1.6.1](https://github.com/pramsey/pgsql-http/archive/refs/tags/v1.6.1.tar.gz) | HTTP client for Postgres |
| [pgtap](https://github.com/theory/pgtap/archive/v1.2.0.tar.gz) | [1.2.0](https://github.com/theory/pgtap/archive/v1.2.0.tar.gz) | A unit testing framework for PostgreSQL |
| [pgvector](https://github.com/pgvector/pgvector/archive/refs/tags/v0.8.0.tar.gz) | [0.8.0](https://github.com/pgvector/pgvector/archive/refs/tags/v0.8.0.tar.gz) | Open-source vector similarity search for Postgres |
| [plpgsql-check](https://github.com/okbob/plpgsql_check/archive/v2.7.11.tar.gz) | [2.7.11](https://github.com/okbob/plpgsql_check/archive/v2.7.11.tar.gz) | Linter tool for language PL/pgSQL |
| [postgis](https://download.osgeo.org/postgis/source/postgis-3.3.7.tar.gz) | [3.3.7](https://download.osgeo.org/postgis/source/postgis-3.3.7.tar.gz) | Geographic Objects for PostgreSQL |
| [rum](https://github.com/postgrespro/rum/archive/1.3.14.tar.gz) | [1.3.14](https://github.com/postgrespro/rum/archive/1.3.14.tar.gz) | Full text search index method for PostgreSQL |
| [supabase-wrappers](https://github.com/supabase/wrappers/archive/v0.4.4.tar.gz) | [0.4.4](https://github.com/supabase/wrappers/archive/v0.4.4.tar.gz) | Various Foreign Data Wrappers (FDWs) for PostreSQL |
| [supautils](https://github.com/supabase/supautils/archive/refs/tags/v2.6.0.tar.gz) | [2.6.0](https://github.com/supabase/supautils/archive/refs/tags/v2.6.0.tar.gz) | PostgreSQL extension for enhanced security |
| [vault](https://github.com/supabase/vault/archive/refs/tags/v0.2.9.tar.gz) | [0.2.9](https://github.com/supabase/vault/archive/refs/tags/v0.2.9.tar.gz) | Store encrypted secrets in PostgreSQL |
| [wal2json](https://github.com/eulerto/wal2json/archive/wal2json_2_6.tar.gz) | [2_6](https://github.com/eulerto/wal2json/archive/wal2json_2_6.tar.gz) | PostgreSQL JSON output plugin for changeset extraction |
## Additional Goodies
*This is only available for our AWS EC2*

| Goodie | Version | Description |
| ------------- | :-------------: | ------------- |
| [PgBouncer](https://www.pgbouncer.org/) | [1.16.1](http://www.pgbouncer.org/changelog.html#pgbouncer-116x) | Set up Connection Pooling. |
| [PostgREST](https://postgrest.org/en/stable/) | [v12.2.3](https://github.com/PostgREST/postgrest/releases/tag/v12.2.3) | Instantly transform your database into an RESTful API. |
| [WAL-G](https://github.com/wal-g/wal-g#wal-g) | [v2.0.1](https://github.com/wal-g/wal-g/releases/tag/v2.0.1) | Tool for physical database backup and recovery. | -->

## Install

See all installation instructions in the [repo wiki](https://github.com/supabase/postgres/wiki).

[![Docker](https://github.com/supabase/postgres/blob/develop/docs/img/docker.png)](https://github.com/supabase/postgres/wiki/Docker)
[![AWS](https://github.com/supabase/postgres/blob/develop/docs/img/aws.png)](https://github.com/supabase/postgres/wiki/AWS-EC2)

<!-- ### Marketplace Images
TODO: find way to automate this
|   | Postgres & Extensions | PgBouncer | PostgREST | WAL-G |
|---|:---:|:---:|:---:|:---:|
| Supabase Postgres |  ✔️   | ❌    | ❌   |  ✔️   |
| Supabase Postgres: PgBouncer Bundle  |  ✔️   |  ✔️  | ❌    |   ✔️ |
| Supabase Postgres: PostgREST Bundle |  ✔️   |  ❌  |  ✔️   |   ✔️ |
| Supabase Postgres: Complete Bundle |  ✔️  |  ✔️   | ✔️   | ✔️   |

#### Availability
|   | AWS ARM | AWS x86 | Digital Ocean x86 |
|---|:---:|:---:|:---:|
| Supabase Postgres | Coming Soon | Coming Soon | Coming Soon |
| Supabase Postgres: PgBouncer Bundle  | Coming Soon | Coming Soon | Coming Soon |
| Supabase Postgres: PostgREST Bundle | Coming Soon | Coming Soon | Coming Soon |
| Supabase Postgres: Complete Bundle | Coming Soon | Coming Soon | Coming Soon |

``` -->

## Motivation

- Make it fast and simple to get started with Postgres.
- Show off a few of Postgres' most exciting features.
- This is the same build we offer at [Supabase](https://supabase.io).
- Open a github issue if you have a feature request

## License

[The PostgreSQL License](https://opensource.org/licenses/postgresql). We realize that licensing is tricky since we are bundling all the various plugins. If we have infringed on any license, let us know and we will make the necessary changes (or remove that extension from this repo).

## Sponsors

We are building the features of Firebase using enterprise-grade, open source products. We support existing communities wherever possible, and if the products don’t exist we build them and open source them ourselves.

[![New Sponsor](https://user-images.githubusercontent.com/10214025/90518111-e74bbb00-e198-11ea-8f88-c9e3c1aa4b5b.png)](https://github.com/sponsors/supabase)