select
  *
from
  pg_wait_sampling_current
where
  false;

select
  *
from
  pg_wait_sampling_history
where
  false;

select
  *
from
  pg_wait_sampling_profile
where
  false;

select pg_wait_sampling_reset_profile();
