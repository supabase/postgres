-- migrate:up
ALTER ROLE postgres SET local_preload_libraries = '$libdir/plugins/safeupdate';

ALTER ROLE postgres SET safeupdate.enabled = 0;


-- migrate:down

