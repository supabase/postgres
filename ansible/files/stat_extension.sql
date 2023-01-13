CREATE SCHEMA IF NOT exists extensions;
CREATE EXTENSION IF NOT EXISTS pg_stat_statements with schema extensions;
CREATE EXTENSION IF NOT EXISTS pg_netstat with schema extensions;
