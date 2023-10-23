-- migrate:up
do $$
begin
  if exists (select from pg_extension where extname = 'pg_cron') then
    revoke all on table cron.job from postgres;
    grant select on table cron.job to postgres with grant option;
  end if;
end $$;

drop event trigger if exists issue_pg_cron_access;
drop function if exists extensions.grant_pg_cron_access();

-- migrate:down
