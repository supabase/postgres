SELECT (SELECT setting FROM pg_settings WHERE name = 'summarize_wal') = 'on' AS summarize_wal_default_ok;
