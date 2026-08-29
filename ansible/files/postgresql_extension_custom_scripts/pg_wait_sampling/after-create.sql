-- Upstream revokes this from PUBLIC (it's the only function of the
-- extension not already granted to PUBLIC); grant it back to postgres so
-- the extension is fully usable without superuser.
grant execute on function pg_wait_sampling_reset_profile() to postgres with grant option;
