show pg_wait_sampling.profile_pid;

show pg_wait_sampling.history_size;

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
