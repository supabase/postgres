begin;
do $_$
begin
  if current_setting('server_version_num')::integer >= 170000 then
    create extension if not exists pg_textsearch with schema "extensions";
  end if;
end
$_$;
rollback;
