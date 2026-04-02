BEGIN;
alter role postgres set session_preload_libraries = 'safeupdate, supautils';
alter role postgres set safeupdate.enabled = 0;
ROLLBACK;
