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
| [hypopg](https://github.com/supabase/hypopg) | [1.4.1](https://github.com/supabase/hypopg/releases/tag/v1.4.1) | Hypothetical Indexes for PostgreSQL |
| [index_advisor](https://github.com/supabase/index_advisor) | [0.2.0](https://github.com/supabase/index_advisor/releases/tag/v0.2.0) | Recommend indexes to improve query performance in PostgreSQL |
| [pg-safeupdate](https://github.com/supabase/pg-safeupdate) | [1.4](https://github.com/supabase/pg-safeupdate/releases/tag/v1.4) | A simple extension to PostgreSQL that requires criteria for UPDATE and DELETE |
| [pg_backtrace](https://github.com/supabase/pg_backtrace) | [1.1](https://github.com/supabase/pg_backtrace/releases/tag/v1.1) | Updated fork of pg_backtrace |
| [pg_cron](https://github.com/supabase/pg_cron) | [1.6.4](https://github.com/supabase/pg_cron/releases/tag/v1.6.4) | Run Cron jobs through PostgreSQL |
| [pg_graphql](https://github.com/supabase/pg_graphql) | [1.5.9](https://github.com/supabase/pg_graphql/releases/tag/v1.5.9) | GraphQL support for PostreSQL |
| [pg_hashids](https://github.com/supabase/pg_hashids) | [cd0e1b31d52b394a0df64079406a14a4f7387cd6](https://github.com/supabase/pg_hashids/releases/tag/vcd0e1b31d52b394a0df64079406a14a4f7387cd6) | Generate short unique IDs in PostgreSQL |
| [pg_jsonschema](https://github.com/supabase/pg_jsonschema) | [0.3.3](https://github.com/supabase/pg_jsonschema/releases/tag/v0.3.3) | JSON Schema Validation for PostgreSQL |
| [pg_net](https://github.com/supabase/pg_net) | [0.14.0](https://github.com/supabase/pg_net/releases/tag/v0.14.0) | Async networking for Postgres |
| [pg_plan_filter](https://github.com/supabase/pg_plan_filter) | [5081a7b5cb890876e67d8e7486b6a64c38c9a492](https://github.com/supabase/pg_plan_filter/releases/tag/v5081a7b5cb890876e67d8e7486b6a64c38c9a492) | Filter PostgreSQL statements by execution plans |
| [pg_repack](https://github.com/supabase/pg_repack) | [1.5.2](https://github.com/supabase/pg_repack/releases/tag/v1.5.2) | Reorganize tables in PostgreSQL databases with minimal locks |
| [pg_stat_monitor](https://github.com/supabase/pg_stat_monitor) | [2.1.0](https://github.com/supabase/pg_stat_monitor/releases/tag/v2.1.0) | Query Performance Monitoring Tool for PostgreSQL |
| [pg_tle](https://github.com/supabase/pg_tle) | [1.4.0](https://github.com/supabase/pg_tle/releases/tag/v1.4.0) | Framework for 'Trusted Language Extensions' in PostgreSQL |
| [pgaudit](https://github.com/supabase/pgaudit) | [1.7.0](https://github.com/supabase/pgaudit/releases/tag/v1.7.0) | Open Source PostgreSQL Audit Logging |
| [pgjwt](https://github.com/supabase/pgjwt) | [9742dab1b2f297ad3811120db7b21451bca2d3c9](https://github.com/supabase/pgjwt/releases/tag/v9742dab1b2f297ad3811120db7b21451bca2d3c9) | PostgreSQL implementation of JSON Web Tokens |
| [pgmq](https://github.com/supabase/pgmq) | [1.4.4](https://github.com/supabase/pgmq/releases/tag/v1.4.4) | A lightweight message queue. Like AWS SQS and RSMQ but on Postgres. |
| [pgroonga](https://github.com/supabase/pgroonga) | [3.2.5](https://github.com/supabase/pgroonga/releases/tag/v3.2.5) | A PostgreSQL extension to use Groonga as the index |
| [pgrouting](https://github.com/supabase/pgrouting) | [3.4.1](https://github.com/supabase/pgrouting/releases/tag/v3.4.1) | A PostgreSQL/PostGIS extension that provides geospatial routing functionality |
| [pgsodium](https://github.com/supabase/pgsodium) | [3.1.8](https://github.com/supabase/pgsodium/releases/tag/v3.1.8) | Modern cryptography for PostgreSQL |
| [pgsql-http](https://github.com/supabase/pgsql-http) | [1.6.1](https://github.com/supabase/pgsql-http/releases/tag/v1.6.1) | HTTP client for Postgres |
| [pgtap](https://github.com/supabase/pgtap) | [1.2.0](https://github.com/supabase/pgtap/releases/tag/v1.2.0) | A unit testing framework for PostgreSQL |
| [pgvector](https://github.com/supabase/pgvector) | [0.8.0](https://github.com/supabase/pgvector/releases/tag/v0.8.0) | Open-source vector similarity search for Postgres |
| [plpgsql-check](https://github.com/supabase/plpgsql-check) | [2.7.11](https://github.com/supabase/plpgsql-check/releases/tag/v2.7.11) | Linter tool for language PL/pgSQL |
| [plv8](https://github.com/supabase/plv8) | [3.1.10](https://github.com/supabase/plv8/releases/tag/v3.1.10) | V8 Engine Javascript Procedural Language add-on for PostgreSQL |
| [postgis](https://github.com/supabase/postgis) | [3.3.7](https://github.com/supabase/postgis/releases/tag/v3.3.7) | Geographic Objects for PostgreSQL |
| [rum](https://github.com/supabase/rum) | [1.3.14](https://github.com/supabase/rum/releases/tag/v1.3.14) | Full text search index method for PostgreSQL |
| [supabase-wrappers](https://github.com/supabase/supabase-wrappers) | [0.4.4](https://github.com/supabase/supabase-wrappers/releases/tag/v0.4.4) | Various Foreign Data Wrappers (FDWs) for PostreSQL |
| [supautils](https://github.com/supabase/supautils) | [2.6.0](https://github.com/supabase/supautils/releases/tag/v2.6.0) | PostgreSQL extension for enhanced security |
| [timescaledb-apache](https://github.com/supabase/timescaledb-apache) | [2.16.1](https://github.com/supabase/timescaledb-apache/releases/tag/v2.16.1) | Scales PostgreSQL for time-series data via automatic partitioning across time and space |
| [vault](https://github.com/supabase/vault) | [0.2.9](https://github.com/supabase/vault/releases/tag/v0.2.9) | Store encrypted secrets in PostgreSQL |
| [wal2json](https://github.com/supabase/wal2json) | [2_6](https://github.com/supabase/wal2json/releases/tag/v2_6) | PostgreSQL JSON output plugin for changeset extraction |

### PostgreSQL orioledb-17 Extensions
| Extension | Version | Description |
| ------------- | :-------------: | ------------- |
| [hypopg](https://github.com/supabase/hypopg) | [1.4.1](https://github.com/supabase/hypopg/releases/tag/v1.4.1) | Hypothetical Indexes for PostgreSQL |
| [index_advisor](https://github.com/supabase/index_advisor) | [0.2.0](https://github.com/supabase/index_advisor/releases/tag/v0.2.0) | Recommend indexes to improve query performance in PostgreSQL |
| ['$name'](https://github.com/orioledb/orioledb) | orioledb | orioledb |
| [pg-safeupdate](https://github.com/supabase/pg-safeupdate) | [1.4](https://github.com/supabase/pg-safeupdate/releases/tag/v1.4) | A simple extension to PostgreSQL that requires criteria for UPDATE and DELETE |
| [pg_backtrace](https://github.com/supabase/pg_backtrace) | [1.1](https://github.com/supabase/pg_backtrace/releases/tag/v1.1) | Updated fork of pg_backtrace |
| [pg_cron](https://github.com/supabase/pg_cron) | [1.6.4](https://github.com/supabase/pg_cron/releases/tag/v1.6.4) | Run Cron jobs through PostgreSQL |
| [pg_graphql](https://github.com/supabase/pg_graphql) | [1.5.9](https://github.com/supabase/pg_graphql/releases/tag/v1.5.9) | GraphQL support for PostreSQL |
| [pg_hashids](https://github.com/supabase/pg_hashids) | [cd0e1b31d52b394a0df64079406a14a4f7387cd6](https://github.com/supabase/pg_hashids/releases/tag/vcd0e1b31d52b394a0df64079406a14a4f7387cd6) | Generate short unique IDs in PostgreSQL |
| [pg_jsonschema](https://github.com/supabase/pg_jsonschema) | [0.3.3](https://github.com/supabase/pg_jsonschema/releases/tag/v0.3.3) | JSON Schema Validation for PostgreSQL |
| [pg_net](https://github.com/supabase/pg_net) | [0.14.0](https://github.com/supabase/pg_net/releases/tag/v0.14.0) | Async networking for Postgres |
| [pg_plan_filter](https://github.com/supabase/pg_plan_filter) | [5081a7b5cb890876e67d8e7486b6a64c38c9a492](https://github.com/supabase/pg_plan_filter/releases/tag/v5081a7b5cb890876e67d8e7486b6a64c38c9a492) | Filter PostgreSQL statements by execution plans |
| [pg_repack](https://github.com/supabase/pg_repack) | [1.5.2](https://github.com/supabase/pg_repack/releases/tag/v1.5.2) | Reorganize tables in PostgreSQL databases with minimal locks |
| [pg_stat_monitor](https://github.com/supabase/pg_stat_monitor) | [2.1.0](https://github.com/supabase/pg_stat_monitor/releases/tag/v2.1.0) | Query Performance Monitoring Tool for PostgreSQL |
| [pg_tle](https://github.com/supabase/pg_tle) | [1.4.0](https://github.com/supabase/pg_tle/releases/tag/v1.4.0) | Framework for 'Trusted Language Extensions' in PostgreSQL |
| [pgaudit](https://github.com/supabase/pgaudit) | [17.0](https://github.com/supabase/pgaudit/releases/tag/v17.0) | Open Source PostgreSQL Audit Logging |
| [pgjwt](https://github.com/supabase/pgjwt) | [9742dab1b2f297ad3811120db7b21451bca2d3c9](https://github.com/supabase/pgjwt/releases/tag/v9742dab1b2f297ad3811120db7b21451bca2d3c9) | PostgreSQL implementation of JSON Web Tokens |
| [pgmq](https://github.com/supabase/pgmq) | [1.4.4](https://github.com/supabase/pgmq/releases/tag/v1.4.4) | A lightweight message queue. Like AWS SQS and RSMQ but on Postgres. |
| [pgroonga](https://github.com/supabase/pgroonga) | [3.2.5](https://github.com/supabase/pgroonga/releases/tag/v3.2.5) | A PostgreSQL extension to use Groonga as the index |
| [pgrouting](https://github.com/supabase/pgrouting) | [3.4.1](https://github.com/supabase/pgrouting/releases/tag/v3.4.1) | A PostgreSQL/PostGIS extension that provides geospatial routing functionality |
| [pgsodium](https://github.com/supabase/pgsodium) | [3.1.8](https://github.com/supabase/pgsodium/releases/tag/v3.1.8) | Modern cryptography for PostgreSQL |
| [pgsql-http](https://github.com/supabase/pgsql-http) | [1.6.1](https://github.com/supabase/pgsql-http/releases/tag/v1.6.1) | HTTP client for Postgres |
| [pgtap](https://github.com/supabase/pgtap) | [1.2.0](https://github.com/supabase/pgtap/releases/tag/v1.2.0) | A unit testing framework for PostgreSQL |
| [pgvector](https://github.com/supabase/pgvector) | [0.8.0](https://github.com/supabase/pgvector/releases/tag/v0.8.0) | Open-source vector similarity search for Postgres |
| [plpgsql-check](https://github.com/supabase/plpgsql-check) | [2.7.11](https://github.com/supabase/plpgsql-check/releases/tag/v2.7.11) | Linter tool for language PL/pgSQL |
| [postgis](https://github.com/supabase/postgis) | [3.3.7](https://github.com/supabase/postgis/releases/tag/v3.3.7) | Geographic Objects for PostgreSQL |
| [rum](https://github.com/supabase/rum) | [1.3.14](https://github.com/supabase/rum/releases/tag/v1.3.14) | Full text search index method for PostgreSQL |
| [supabase-wrappers](https://github.com/supabase/supabase-wrappers) | [0.4.4](https://github.com/supabase/supabase-wrappers/releases/tag/v0.4.4) | Various Foreign Data Wrappers (FDWs) for PostreSQL |
| [supautils](https://github.com/supabase/supautils) | [2.6.0](https://github.com/supabase/supautils/releases/tag/v2.6.0) | PostgreSQL extension for enhanced security |
| [vault](https://github.com/supabase/vault) | [0.2.9](https://github.com/supabase/vault/releases/tag/v0.2.9) | Store encrypted secrets in PostgreSQL |
| [wal2json](https://github.com/supabase/wal2json) | [2_6](https://github.com/supabase/wal2json/releases/tag/v2_6) | PostgreSQL JSON output plugin for changeset extraction |
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