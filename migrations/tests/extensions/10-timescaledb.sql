begin;
do $_$
begin
  if not exists (select 1 from pg_extension where extname = 'orioledb') then
    create extension if not exists timescaledb with schema "extensions";
  end if;
end
$_$;
rollback;
