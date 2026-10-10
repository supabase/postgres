-- migrate:up
ALTER ROLE postgres SET session_preload_libraries = supautils, safeupdate;

ALTER ROLE postgres SET safeupdate.enabled = 0;

-- migrate:down
