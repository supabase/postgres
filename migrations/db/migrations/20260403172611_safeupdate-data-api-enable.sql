-- migrate:up
ALTER ROLE anon SET session_preload_libraries = '$libdir/plugins/safeupdate';
ALTER ROLE authenticator SET session_preload_libraries = 'supautils, $libdir/plugins/safeupdate';
ALTER ROLE authenticated SET session_preload_libraries = '$libdir/plugins/safeupdate';
ALTER ROLE postgres SET local_preload_libraries = '$libdir/plugins/safeupdate';

ALTER ROLE anon SET safeupdate.enabled = 1;
ALTER ROLE authenticator SET safeupdate.enabled = 1;
ALTER ROLE authenticated SET safeupdate.enabled = 1;
ALTER ROLE postgres SET safeupdate.enabled = 0;


-- migrate:down

