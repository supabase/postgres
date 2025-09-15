do $$
declare
  is_super boolean;
begin
  is_super = (
    select usesuper
    from pg_user
    where usename = 'postgres'
  );

  -- Need to be superuser to own FDWs, so we temporarily make postgres superuser.
  if not is_super then
    alter role postgres superuser;
  end if;

  alter foreign data wrapper postgres_fdw owner to postgres;

  if not is_super then
    alter role postgres nosuperuser;
  end if;
end $$;
