BEGIN;
SELECT plan(5);

-- supautils is loaded at session start via session_preload_libraries
SELECT ok(
  current_setting('session_preload_libraries') ~ '\msupautils\M',
  'supautils is in session_preload_libraries'
);

-- so its settings exist and are populated from supautils.conf
SELECT ok(
  coalesce(current_setting('supautils.privileged_extensions', true), '') <> '',
  'supautils.privileged_extensions is set and non-empty'
);

-- spot-check a few stable entries rather than the whole list
SELECT ok(
  string_to_array(replace(current_setting('supautils.privileged_extensions', true), ' ', ''), ',')
    @> ARRAY['pg_cron']::text[],
  'pg_cron is a privileged extension'
);

SELECT ok(
  string_to_array(replace(current_setting('supautils.privileged_extensions', true), ' ', ''), ',')
    @> ARRAY['pgsodium']::text[],
  'pgsodium is a privileged extension'
);

SELECT ok(
  string_to_array(replace(current_setting('supautils.privileged_extensions', true), ' ', ''), ',')
    @> ARRAY['vector']::text[],
  'vector is a privileged extension'
);

SELECT * FROM finish();
ROLLBACK;
