create role postgres;
create extension address_standardizer;
create extension address_standardizer_data_us;
create extension adminpack;
create extension amcheck;
create extension autoinc;
create extension bloom;
create extension btree_gin;
create extension btree_gist;
create extension citext;
create extension cube;
create extension dblink;
create extension dict_int;
create extension dict_xsyn;
create extension earthdistance;
create extension file_fdw;
create extension fuzzystrmatch;
create extension http;
create extension hstore;
create extension hypopg;
create extension index_advisor;
create extension insert_username;
create extension intagg;
create extension intarray;
create extension isn;
create extension lo;
create extension ltree;
create extension moddatetime;
create extension old_snapshot;
create extension pageinspect;
create extension pg_buffercache;

/*
TODO: Does not enable locally mode
requires a change to postgresql.conf to set
cron.database_name = 'testing'
*/
-- create extension pg_cron;

create extension pg_net;
create extension pg_graphql;
create extension pg_freespacemap;
create extension pg_hashids;
create extension pg_prewarm;
create extension pgmq;
create extension pg_jsonschema;
create extension pg_repack;
create extension pg_stat_monitor;
create extension pg_stat_statements;
create extension pg_surgery;
create extension pg_tle;
create extension pg_trgm;
create extension pg_visibility;
create extension pg_walinspect;
create extension pgaudit;
create extension pgcrypto;
create extension pgtap;
create extension pgjwt;
create extension pgroonga;
create extension pgroonga_database;
create extension pgsodium;
create extension pgrowlocks;
create extension pgstattuple;
create extension plpgsql_check;

create extension plv8;
create extension plcoffee;
create extension plls;

create extension postgis;
create extension postgis_raster;
create extension postgis_sfcgal;
create extension postgis_tiger_geocoder;
create extension postgis_topology;
create extension pgrouting; -- requires postgis
create extension postgres_fdw;
create extension rum;
create extension refint;
create extension seg;
create extension sslinfo;
create extension supabase_vault;
create extension tablefunc;
create extension tcn;
create extension timescaledb;
create extension tsm_system_rows;
create extension tsm_system_time;
create extension unaccent;
create extension "uuid-ossp";
create extension vector;
create extension wrappers;
create extension xml2;


 
 
 

CREATE EXTENSION IF NOT EXISTS pg_backtrace;
