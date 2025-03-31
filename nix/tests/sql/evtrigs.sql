SELECT
  e.evtname,
  e.evtowner::regrole AS evtowner,
  e.evtfoid::regproc AS evtfunction,
  p.proowner::regrole AS function_owner
FROM pg_event_trigger e
JOIN pg_proc p
  ON e.evtfoid = p.oid
WHERE p.prorettype = 'event_trigger'::regtype;
