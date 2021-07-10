# Postgres + goodies

Unmodified Postgres with some useful plugins. Our goal with this repo is not to modify Postgres, but to provide some of the most common extensions with a one-click install.

## Primary Features
- ✅ Postgres [13](https://www.postgresql.org/about/news/postgresql-13-released-2077/).
- ✅ Ubuntu 20.04 (Focal Fossa).
- ✅ [wal_level](https://www.postgresql.org/docs/current/runtime-config-wal.html) = logical and [max_replication_slots](https://www.postgresql.org/docs/current/runtime-config-replication.html) = 5. Ready for replication.
- ✅ [Large Systems Extensions](https://github.com/aws/aws-graviton-getting-started#building-for-graviton-and-graviton2). Enabled for ARM images.

## Extensions 
| Extension | Description |
| ------------- | ------------- |
| [Postgres contrib modules](https://www.postgresql.org/docs/current/contrib.html) | Because everyone should enable `pg_stat_statements`. |
| [PostGIS](https://postgis.net/) | Postgres' most popular extension - support for geographic objects. |
| [pgRouting](https://pgrouting.org/) | Extension of PostGIS - provides geospatial routing functionalities. |
| [pgTAP](https://pgtap.org/) | Unit Testing for Postgres. |
| [pg_cron](https://github.com/citusdata/pg_cron) | Run CRON jobs inside Postgres. |
| [pgAudit](https://www.pgaudit.org/) | Generate highly compliant audit logs. |
| [pgjwt](https://github.com/michelp/pgjwt) | Generate JSON Web Tokens (JWT) in Postgres. |
| [pgsql-http](https://github.com/pramsey/pgsql-http) | HTTP client for Postgres. |
| [plpgsql_check](https://github.com/okbob/plpgsql_check) | Linter tool for PL/pgSQL. |
| [pg-safeupdate](https://github.com/eradman/pg-safeupdate) | Protect your data from accidental updates or deletes. |
| [wal2json](https://github.com/eulerto/wal2json) | JSON output plugin for logical replication decoding. |
| [PL/Java](https://github.com/tada/pljava) | Write in Java functions in Postgres. |
| [plv8](https://github.com/plv8/plv8) | Write in Javascript functions in Postgres. |

Can't find your favorite extension? Suggest for it to be added into future versions [here](https://github.com/supabase/supabase/discussions/679)!

## Enhanced Security
Aside from having [ufw](https://help.ubuntu.com/community/UFW),[fail2ban](https://www.fail2ban.org/wiki/index.php/Main_Page), and [unattended-upgrades](https://wiki.debian.org/UnattendedUpgrades) installed, we also have the following enhancements in place: 
| Enhancement | Description |
| ------------- | ------------- |
| fail2ban filter for PostgreSQL access | Monitors for brute force attempts over at port `5432`. |
| fail2ban filter for PgBouncer access | Monitors for brute force attempts over at port `6543`. |

## Additional Goodies
| Goodie | Description |
| ------------- | ------------- |
| [PgBouncer](https://postgis.net/) | Set up Connection Pooling. |
| [PostgREST](https://postgrest.org/en/stable/) | Instantly transform your database into an RESTful API. |
| [WAL-G](https://github.com/wal-g/wal-g#wal-g) | Tool for physical database backup and recovery. |

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

Set the `supabase_internal` flag to `false` to avoid baking in components that are specific to Supabase's hosted offering.

```bash
$ time packer build -timestamp-ui \
  -var "ansible_arguments=--skip-tags,update-only,-v,-e,supabase_internal='false'" \
  amazon-arm.json
```

## Motivation

After talking to a lot of techies, we've found that most believe Postgres is the best (operational) database but they _still_ choose other databases. This is overwhelmingly because "the other one was quicker/easier". Our goal is to make it fast and simple to get started with Postgres, so that we never hear that excuse again.

Our secondary goal is to show off a few of Postgres' most exciting features. This is to convince new developers to choose it over other database (a decision we hope they'll appreciate once they start scaling).

Finally, this is the same build we offer at [Supabase](https://supabase.io), and everything we do is opensource. This repo makes it easy to _install_ Postgres, Supabase makes it easy to _use_ Postgres.

## Roadmap

- [Support for more images](https://github.com/supabase/postgres/issues/4)
- [Vote for more plugins/extensions](https://github.com/supabase/postgres/issues/5)
- Open a github issue if you have a feature request

## License

[The PostgreSQL License](https://opensource.org/licenses/postgresql). We realize that licensing is tricky since we are bundling all the various plugins. If we have infringed on any license, let us know and we will make the necessary changes (or remove that extension from this repo).

## Sponsors

We are building the features of Firebase using enterprise-grade, open source products. We support existing communities wherever possible, and if the products don’t exist we build them and open source them ourselves.

[![New Sponsor](https://user-images.githubusercontent.com/10214025/90518111-e74bbb00-e198-11ea-8f88-c9e3c1aa4b5b.png)](https://github.com/sponsors/supabase)
