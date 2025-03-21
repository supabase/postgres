select proname, proowner::regrole
from pg_proc where prorettype = 'event_trigger'::regtype
order by proname;
