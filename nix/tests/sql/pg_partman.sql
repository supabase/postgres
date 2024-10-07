create schema if not exists partman_test;

/*
Simple Time Based: 1 Partition Per Day

For native partitioning, you must start with a parent table that has already been set up to be partitioned in the desired type. Currently pg_partman only supports the RANGE type of partitioning (both for time & id). You cannot turn a non-partitioned table into the parent table of a partitioned set, which can make migration a challenge. This document will show you some techniques for how to manage this later. For now, we will start with a brand new table in this example. Any non-unique indexes can also be added to the parent table in PG11+ and they will automatically be created on all child tables.
*/

create table partman_test.time_taptest_table(
  col1 int,
  col2 text default 'stuff',
  col3 timestamptz not null default now()
)
  partition by range (col3);

create index on partman_test.time_tap (col3);

/*
Unique indexes (including primary keys) cannot be created on a natively partitioned parent unless they include the partition key. For time-based partitioning that generally doesn't work out since that would limit only a single timestamp value in each child table. pg_partman helps to manage this by using a template table to manage properties that currently are not supported by native partitioning. Note that this does not solve the issue of the constraint not being enforced across the entire partition set. See the main documentation to see which properties are managed by the template.

Manually create the template table first so that when we run create_parent() the initial child tables that are created will have a primary key. If you do not supply a template table to pg_partman, it will create one for you in the schema that you installed the extension to. However properties you add to that template are only then applied to newly created child tables after that point. You will have to retroactively apply those properties manually to any child tables that already existed.
*/

create table partman_test.time_taptest_table_template (like partman_test.time_taptest_table);

alter table partman_test.time_taptest_table_template add primary key (col1);

/*
Review tables in the partman_test schema
*/

select
  table_name,
  table_type
from
  information_schema.tables
where
  table_schema = 'partman_test'
order by
  table_name,
  table_type;


select public.create_parent(
    p_parent_table := 'partman_test.time_taptest_table',
    p_control := 'col3',
    p_interval := '1 day',
    p_template_table := 'partman_test.time_taptest_table_template'
);

/*
Review tables in the partman_test schema, which should now include daily partitions
*/

select
  -- dates in partition names are variable, so reduced to the prefix
  substring(table_name, 1, 21) as table_prefix,
  table_type
from
  information_schema.tables
where
  table_schema = 'partman_test'
order by
  table_name;


/*
Confirm maintenance proc runs without issue
*/
call public.run_maintenance_proc();

/*
Make sure the background worker is NOT enabled.
This is intentional. We document using pg_cron to schedule calls to
public.run_maintenance_proc(). That is consistent with other providers.
*/
select
  application_name
from
  pg_stat_activity
where
  application_name = 'pg_partman_bgw';

-- Cleanup
drop schema partman_test cascade;
