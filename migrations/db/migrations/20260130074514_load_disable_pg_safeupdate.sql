-- migrate:up
ALTER ROLE authenticated SET session_preload_libraries = 'safeupdate';
ALTER ROLE anon SET session_preload_libraries = 'safeupdate';
ALTER ROLE postgres SET session_preload_libraries = 'safeupdate';
ALTER ROLE postgres SET safeupdate.enabled=0;

-- migrate:down

