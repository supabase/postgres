# Postgres + goodies

Unmodified Postgres with some useful plugins. Our goal with this repo is not to modify Postgres, but to provide some of the most common extensions with a one-click install.

## Primary Features
- ✅ Postgres [15](https://www.postgresql.org/about/news/postgresql-15-released-2526/).
- ✅ Ubuntu 20.04 (Focal Fossa).
- ✅ [wal_level](https://www.postgresql.org/docs/current/runtime-config-wal.html) = logical and [max_replication_slots](https://www.postgresql.org/docs/current/runtime-config-replication.html) = 5. Ready for replication.
- ✅ [Large Systems Extensions](https://github.com/aws/aws-graviton-getting-started#building-for-graviton-and-graviton2). Enabled for ARM images.

## Extensions 
| Extension | Version | Description |
| ------------- | :-------------: | ------------- |
| [Postgres contrib modules](https://www.postgresql.org/docs/current/contrib.html) | - | Because everyone should enable `pg_stat_statements`. |
| [PostGIS](https://postgis.net/) | [3.3.2](https://git.osgeo.org/gitea/postgis/postgis/raw/tag/3.3.2/NEWS) | Postgres' most popular extension - support for geographic objects. |
| [pgRouting](https://pgrouting.org/) | [v3.4.1](https://github.com/pgRouting/pgrouting/releases/tag/v3.4.1) | Extension of PostGIS - provides geospatial routing functionalities. |
| [pgTAP](https://pgtap.org/) | [v1.2.0](https://github.com/theory/pgtap/releases/tag/v1.2.0) | Unit Testing for Postgres. |
| [pg_cron](https://github.com/citusdata/pg_cron) | [v1.4.2](https://github.com/citusdata/pg_cron/releases/tag/v1.4.2) | Run CRON jobs inside Postgres. |
| [pgAudit](https://www.pgaudit.org/) | [1.7.0](https://github.com/pgaudit/pgaudit/releases/tag/1.7.0) | Generate highly compliant audit logs. |
| [pgjwt](https://github.com/michelp/pgjwt) | [commit](https://github.com/michelp/pgjwt/commit/9742dab1b2f297ad3811120db7b21451bca2d3c9) | Generate JSON Web Tokens (JWT) in Postgres. |
| [pgsql-http](https://github.com/pramsey/pgsql-http) | [1.5.0](https://github.com/pramsey/pgsql-http/releases/tag/v1.5.0) | HTTP client for Postgres. |
| [plpgsql_check](https://github.com/okbob/plpgsql_check) | [2.2.3](https://github.com/okbob/plpgsql_check/releases/tag/v2.2.3) | Linter tool for PL/pgSQL. |
| [pg-safeupdate](https://github.com/eradman/pg-safeupdate) | [1.4](https://github.com/eradman/pg-safeupdate/releases/tag/1.4) | Protect your data from accidental updates or deletes. |
| [wal2json](https://github.com/eulerto/wal2json) | [commit](https://github.com/eulerto/wal2json/commit/53b548a29ebd6119323b6eb2f6013d7c5fe807ec) | JSON output plugin for logical replication decoding. |
| [PL/Java](https://github.com/tada/pljava) | [1.6.4](https://github.com/tada/pljava/releases/tag/V1_6_4) | Write in Java functions in Postgres. |
| [plv8](https://github.com/plv8/plv8) | [commit](https://github.com/plv8/plv8/commit/bcddd92f71530e117f2f98b92d206dafe824f73a) | Write in Javascript functions in Postgres. |
| [pg_plan_filter](https://github.com/pgexperts/pg_plan_filter) | [commit](https://github.com/pgexperts/pg_plan_filter/commit/5081a7b5cb890876e67d8e7486b6a64c38c9a492) | Only allow statements that fulfill set criteria to be executed. |
| [pg_net](https://github.com/supabase/pg_net) | [v0.6.1](https://github.com/supabase/pg_net/releases/tag/v0.6.1) | Expose the SQL interface for async networking. |
| [rum](https://github.com/postgrespro/rum) | [1.3.13](https://github.com/postgrespro/rum/releases/tag/1.3.13) | An alternative to the GIN index. |
| [pg_hashids](https://github.com/iCyberon/pg_hashids) | [commit](https://github.com/iCyberon/pg_hashids/commit/83398bcbb616aac2970f5e77d93a3200f0f28e74) | Generate unique identifiers from numbers. |
| [pgsodium](https://github.com/michelp/pgsodium) | [3.1.0](https://github.com/michelp/pgsodium/releases/tag/2.0.0) | Modern encryption API using libsodium. |
| [pg_stat_monitor](https://github.com/percona/pg_stat_monitor) | [1.0.1](https://github.com/percona/pg_stat_monitor/releases/tag/1.0.1) | Query Performance Monitoring Tool for PostgreSQL


Can't find your favorite extension? Suggest for it to be added into future releases [here](https://github.com/supabase/supabase/discussions/679)!

## Enhanced Security
*This is only available for our AWS EC2/ DO Droplet images*

Aside from having [ufw](https://help.ubuntu.com/community/UFW),[fail2ban](https://www.fail2ban.org/wiki/index.php/Main_Page), and [unattended-upgrades](https://wiki.debian.org/UnattendedUpgrades) installed, we also have the following enhancements in place: 
| Enhancement | Description |
| ------------- | ------------- |
| [fail2ban filter](https://github.com/supabase/postgres/blob/develop/ansible/files/fail2ban_config/filter-postgresql.conf.j2) for PostgreSQL access | Monitors for brute force attempts over at port `5432`. |
| [fail2ban filter](https://github.com/supabase/postgres/blob/develop/ansible/files/fail2ban_config/filter-pgbouncer.conf.j2) for PgBouncer access | Monitors for brute force attempts over at port `6543`. |

## Additional Goodies
*This is only available for our AWS EC2/ DO Droplet images*

| Goodie | Version | Description |
| ------------- | :-------------: | ------------- |
| [PgBouncer](https://www.pgbouncer.org/) | [1.16.1](http://www.pgbouncer.org/changelog.html#pgbouncer-116x) | Set up Connection Pooling. |
| [PostgREST](https://postgrest.org/en/stable/) | [v10.1.1](https://github.com/PostgREST/postgrest/releases/tag/v10.1.1) | Instantly transform your database into an RESTful API. |
| [WAL-G](https://github.com/wal-g/wal-g#wal-g) | [v2.0.1](https://github.com/wal-g/wal-g/releases/tag/v2.0.1) | Tool for physical database backup and recovery. |

## Install

See all installation instructions in the [repo wiki](https://github.com/supabase/postgres/wiki).

[![Docker](https://github.com/supabase/postgres/blob/master/docs/img/docker.png)](https://github.com/supabase/postgres/wiki/Docker)
[![Digital Ocean](https://github.com/supabase/postgres/blob/master/docs/img/digital-ocean.png)](https://github.com/supabase/postgres/wiki/Digital-Ocean)
[![AWS](https://github.com/supabase/postgres/blob/master/docs/img/aws.png)](https://github.com/supabase/postgres/wiki/AWS-EC2)

### Marketplace Images
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

### Quick Build

```bash
$ time packer build -timestamp-ui \
  --var "aws_access_key=<insert aws access key>" \
  --var "aws_secret_key=<insert aws secret key>" \
  --var "ami_regions=<insert desired regions>" \
  amazon-arm.json
```

## Motivation

- Make it fast and simple to get started with Postgres.
- Show off a few of Postgres' most exciting features.
- This is the same build we offer at [Supabase](https://supabase.io).

## Roadmap

- [Support for more images](https://github.com/supabase/postgres/issues/4)
- [Vote for more plugins/extensions](https://github.com/supabase/postgres/issues/5)
- Open a github issue if you have a feature request

## License

[The PostgreSQL License](https://opensource.org/licenses/postgresql). We realize that licensing is tricky since we are bundling all the various plugins. If we have infringed on any license, let us know and we will make the necessary changes (or remove that extension from this repo).

## Sponsors

We are building the features of Firebase using enterprise-grade, open source products. We support existing communities wherever possible, and if the products don’t exist we build them and open source them ourselves.

[![New Sponsor](https://user-images.githubusercontent.com/10214025/90518111-e74bbb00-e198-11ea-8f88-c9e3c1aa4b5b.png)](https://github.com/sponsors/supabase)
