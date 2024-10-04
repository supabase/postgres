#! /usr/bin/env bash

# Common functions and variables used by initiate.sh and complete.sh

REPORTING_PROJECT_REF="ihmaxnjpcccasmrbkpvo"
REPORTING_CREDENTIALS_FILE="/root/upgrade-reporting-credentials"

REPORTING_ANON_KEY=""
if [ -f "$REPORTING_CREDENTIALS_FILE" ]; then
    REPORTING_ANON_KEY=$(cat "$REPORTING_CREDENTIALS_FILE")
fi

# shellcheck disable=SC2120
# Arguments are passed in other files
function run_sql {
    psql -h localhost -U supabase_admin -d postgres "$@"
}

function ship_logs {
    LOG_FILE=$1

    if [ -z "$REPORTING_ANON_KEY" ]; then
        echo "No reporting key found. Skipping log upload."
        return 0
    fi

    if [ ! -f "$LOG_FILE" ]; then
        echo "No log file found. Skipping log upload."
        return 0
    fi

    if [ ! -s "$LOG_FILE" ]; then
        echo "Log file is empty. Skipping log upload."
        return 0
    fi

    HOSTNAME=$(hostname)
    DERIVED_REF="${HOSTNAME##*-}"

    printf -v BODY '{ "ref": "%s", "step": "%s", "content": %s }' "$DERIVED_REF" "completion" "$(cat "$LOG_FILE" | jq -Rs '.')"
    curl -sf -X POST "https://$REPORTING_PROJECT_REF.supabase.co/rest/v1/error_logs" \
         -H "apikey: ${REPORTING_ANON_KEY}" \
         -H 'Content-type: application/json' \
         -d "$BODY"
}

function retry {
  local retries=$1
  shift

  local count=0
  until "$@"; do
    exit=$?
    wait=$((2 ** (count + 1)))
    count=$((count + 1))
    if [ $count -lt "$retries" ]; then
        echo "Command $* exited with code $exit, retrying..."
        sleep $wait
    else
        echo "Command $* exited with code $exit, no more retries left."
        return $exit
    fi
  done
  return 0
}

CI_stop_postgres() {
    BINDIR=$(pg_config --bindir)
    ARG=${1:-""}

    if [ "$ARG" = "--new-bin" ]; then
        BINDIR="/tmp/pg_upgrade_bin/$PG_MAJOR_VERSION/bin"
    fi

    su postgres -c "$BINDIR/pg_ctl stop -o '-c config_file=/etc/postgresql/postgresql.conf' -l /tmp/postgres.log"
}

CI_start_postgres() {
    BINDIR=$(pg_config --bindir)
    ARG=${1:-""}

    if [ "$ARG" = "--new-bin" ]; then
        BINDIR="/tmp/pg_upgrade_bin/$PG_MAJOR_VERSION/bin"
    fi

    su postgres -c "$BINDIR/pg_ctl start -o '-c config_file=/etc/postgresql/postgresql.conf' -l /tmp/postgres.log"
}

swap_postgres_and_supabase_admin() {
    run_sql <<'EOSQL'
alter database postgres connection limit 0;
select pg_terminate_backend(pid) from pg_stat_activity where backend_type = 'client backend' and pid != pg_backend_pid();
EOSQL
    run_sql <<'EOSQL'
set statement_timeout = '600s';
begin;
create role supabase_tmp superuser;
set session authorization supabase_tmp;

do $$
begin
  if exists (select from pg_extension where extname = 'timescaledb') then
    execute(format('select %s.timescaledb_pre_restore()', (select pronamespace::regnamespace from pg_proc where proname = 'timescaledb_pre_restore')));
  end if;
end
$$;

do $$
declare
  postgres_rolpassword text := (select rolpassword from pg_authid where rolname = 'postgres');
  supabase_admin_rolpassword text := (select rolpassword from pg_authid where rolname = 'supabase_admin');
  role_settings jsonb[] := (
    select coalesce(array_agg(jsonb_build_object('database', d.datname, 'role', a.rolname, 'configs', s.setconfig)), '{}')
    from pg_db_role_setting s
    left join pg_database d on d.oid = s.setdatabase
    join pg_authid a on a.oid = s.setrole
    where a.rolname in ('postgres', 'supabase_admin')
  );
  event_triggers jsonb[] := (select coalesce(array_agg(jsonb_build_object('name', evtname)), '{}') from pg_event_trigger where evtowner = 'postgres'::regrole);
  user_mappings jsonb[] := (
    select coalesce(array_agg(jsonb_build_object('oid', um.oid, 'role', a.rolname, 'server', s.srvname, 'options', um.umoptions)), '{}')
    from pg_user_mapping um
    join pg_authid a on a.oid = um.umuser
    join pg_foreign_server s on s.oid = um.umserver
    where a.rolname in ('postgres', 'supabase_admin')
  );
  -- Objects can have initial privileges either by having those privileges set
  -- when the system is initialized (by initdb) or when the object is created
  -- during a CREATE EXTENSION and the extension script sets initial
  -- privileges using the GRANT system. (https://www.postgresql.org/docs/current/catalog-pg-init-privs.html)
  -- We only care about swapping init_privs for extensions.
  init_privs jsonb[] := (
    select coalesce(array_agg(jsonb_build_object('objoid', objoid, 'classoid', classoid, 'initprivs', initprivs::text)), '{}')
    from pg_init_privs
    where privtype = 'e'
  );
  default_acls jsonb[] := (
    select coalesce(array_agg(jsonb_build_object('oid', d.oid, 'role', a.rolname, 'schema', n.nspname, 'objtype', d.defaclobjtype, 'acl', defaclacl::text)), '{}')
    from pg_default_acl d
    join pg_authid a on a.oid = d.defaclrole
    left join pg_namespace n on n.oid = d.defaclnamespace
  );
  schemas jsonb[] := (
    select coalesce(array_agg(jsonb_build_object('oid', n.oid, 'owner', a.rolname, 'acl', nspacl::text)), '{}')
    from pg_namespace n
    join pg_authid a on a.oid = n.nspowner
    where true
      and n.nspname != 'information_schema'
      and not starts_with(n.nspname, 'pg_')
  );
  types jsonb[] := (
    select coalesce(array_agg(jsonb_build_object('oid', t.oid, 'owner', a.rolname, 'acl', t.typacl::text)), '{}')
    from pg_type t
    join pg_namespace n on n.oid = t.typnamespace
    join pg_authid a on a.oid = t.typowner
    where true
      and n.nspname != 'information_schema'
      and not starts_with(n.nspname, 'pg_')
      and (
        t.typrelid = 0
        or (
          select
            c.relkind = 'c'
          from
            pg_class c
          where
            c.oid = t.typrelid
        )
      )
      and not exists (
        select
        from
          pg_type el
        where
          el.oid = t.typelem
          and el.typarray = t.oid
      )
  );
  functions jsonb[] := (
    select coalesce(array_agg(jsonb_build_object('oid', p.oid, 'owner', a.rolname, 'kind', p.prokind, 'acl', p.proacl::text)), '{}')
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    join pg_authid a on a.oid = p.proowner
    where true
      and n.nspname != 'information_schema'
      and not starts_with(n.nspname, 'pg_')
  );
  relations jsonb[] := (
    select coalesce(array_agg(jsonb_build_object('oid', c.oid, 'owner', a.rolname, 'acl', c.relacl::text)), '{}')
    from (
      -- Sequences must appear after tables, so we order by relkind
      select * from pg_class order by relkind desc
    ) c
    join pg_namespace n on n.oid = c.relnamespace
    join pg_authid a on a.oid = c.relowner
    where true
      and n.nspname != 'information_schema'
      and not starts_with(n.nspname, 'pg_')
      and c.relkind not in ('c', 'i', 'I')
  );
  rec record;
  obj jsonb;
begin
  set local search_path = '';

  if exists (select from pg_event_trigger where evtname = 'pgsodium_trg_mask_update') then
    alter event trigger pgsodium_trg_mask_update disable;
  end if;

  alter role postgres rename to supabase_admin_;
  alter role supabase_admin rename to postgres;
  alter role supabase_admin_ rename to supabase_admin;

  -- role grants
  for rec in
    select * from pg_auth_members
  loop
    execute(format('revoke %s from %s;', rec.roleid::regrole, rec.member::regrole));
    execute(format(
      'grant %s to %s %s granted by %s;',
      case
        when rec.roleid = 'postgres'::regrole then 'supabase_admin'
        when rec.roleid = 'supabase_admin'::regrole then 'postgres'
        else rec.roleid::regrole
      end,
      case
        when rec.member = 'postgres'::regrole then 'supabase_admin'
        when rec.member = 'supabase_admin'::regrole then 'postgres'
        else rec.member::regrole
      end,
      case
        when rec.admin_option then 'with admin option'
        else ''
      end,
      case
        when rec.grantor = 'postgres'::regrole then 'supabase_admin'
        when rec.grantor = 'supabase_admin'::regrole then 'postgres'
        else rec.grantor::regrole
      end
    ));
  end loop;

  -- role passwords
  execute(format('alter role postgres password %L;', postgres_rolpassword));
  execute(format('alter role supabase_admin password %L;', supabase_admin_rolpassword));

  -- role settings
  foreach obj in array role_settings
  loop
    execute(format('alter role %I %s reset all',
                   case when obj->>'role' = 'postgres' then 'supabase_admin' else 'postgres' end,
                   case when obj->>'database' is null then '' else format('in database %I', obj->>'database') end
    ));
  end loop;
  foreach obj in array role_settings
  loop
    for rec in
      select split_part(value, '=', 1) as key, substr(value, strpos(value, '=') + 1) as value
      from jsonb_array_elements_text(obj->'configs')
    loop
      execute(format('alter role %I %s set %I to %s',
                     obj->>'role',
                     case when obj->>'database' is null then '' else format('in database %I', obj->>'database') end,
                     rec.key,
                     -- https://github.com/postgres/postgres/blob/70d1c664f4376fd3499e3b0c6888cf39b65d722b/src/bin/pg_dump/dumputils.c#L861
                     case
                       when rec.key in ('local_preload_libraries', 'search_path', 'session_preload_libraries', 'shared_preload_libraries', 'temp_tablespaces', 'unix_socket_directories')
                         then rec.value
                       else quote_literal(rec.value)
                     end
      ));
    end loop;
  end loop;

  reassign owned by postgres to supabase_admin;

  -- databases
  for rec in
    select * from pg_database where datname not in ('template0')
  loop
    execute(format('alter database %I owner to postgres;', rec.datname));
  end loop;

  -- event triggers
  foreach obj in array event_triggers
  loop
    execute(format('alter event trigger %I owner to postgres;', obj->>'name'));
  end loop;

  -- publications
  for rec in
    select * from pg_publication
  loop
    execute(format('alter publication %I owner to postgres;', rec.pubname));
  end loop;

  -- FDWs
  for rec in
    select * from pg_foreign_data_wrapper
  loop
    execute(format('alter foreign data wrapper %I owner to postgres;', rec.fdwname));
  end loop;

  -- foreign servers
  for rec in
    select * from pg_foreign_server
  loop
    execute(format('alter server %I owner to postgres;', rec.srvname));
  end loop;

  -- user mappings
  foreach obj in array user_mappings
  loop
    execute(format('drop user mapping for %I server %I', case when obj->>'role' = 'postgres' then 'supabase_admin' else 'postgres' end, obj->>'server'));
  end loop;
  foreach obj in array user_mappings
  loop
    execute(format('create user mapping for %I server %I', obj->>'role', obj->>'server'));
    for rec in
      select split_part(value, '=', 1) as key, substr(value, strpos(value, '=') + 1) as value
      from jsonb_array_elements_text(obj->'options')
    loop
      execute(format('alter user mapping for %I server %I options (%I %L)', obj->>'role', obj->>'server', rec.key, rec.value));
    end loop;
  end loop;

  -- init privs
  foreach obj in array init_privs
  loop
    -- We need to modify system catalog directly here because there's no ALTER INIT PRIVILEGES.
    update pg_init_privs set initprivs = (obj->>'initprivs')::aclitem[] where objoid = (obj->>'objoid')::oid and classoid = (obj->>'classoid')::oid;
  end loop;

  -- default acls
  foreach obj in array default_acls
  loop
    for rec in
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode((obj->>'acl')::aclitem[])
    loop
      if obj->>'role' in ('postgres', 'supabase_admin') or rec.grantee::regrole in ('postgres', 'supabase_admin') then
        execute(format('alter default privileges for role %I %s revoke %s on %s from %s'
                     , case when obj->>'role' = 'postgres' then 'supabase_admin'
                            when obj->>'role' = 'supabase_admin' then 'postgres'
                            else obj->>'role'
                       end
                     , case when obj->>'schema' is null then ''
                            else format('in schema %I', obj->>'schema')
                       end
                     , rec.privilege_type
                     , case when obj->>'objtype' = 'r' then 'tables'
                            when obj->>'objtype' = 'S' then 'sequences'
                            when obj->>'objtype' = 'f' then 'functions'
                            when obj->>'objtype' = 'T' then 'types'
                            when obj->>'objtype' = 'n' then 'schemas'
                       end
                     , case when rec.grantee = 'postgres'::regrole then 'supabase_admin'
                            when rec.grantee = 'supabase_admin'::regrole then 'postgres'
                            when rec.grantee = 0 then 'public'
                            else rec.grantee::regrole::text
                       end
                     ));
      end if;
    end loop;
  end loop;

  foreach obj in array default_acls
  loop
    for rec in
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode((obj->>'acl')::aclitem[])
    loop
      if obj->>'role' in ('postgres', 'supabase_admin') or rec.grantee::regrole in ('postgres', 'supabase_admin') then
        execute(format('alter default privileges for role %I %s grant %s on %s to %s %s'
                     , obj->>'role'
                     , case when obj->>'schema' is null then ''
                            else format('in schema %I', obj->>'schema')
                       end
                     , rec.privilege_type
                     , case when obj->>'objtype' = 'r' then 'tables'
                            when obj->>'objtype' = 'S' then 'sequences'
                            when obj->>'objtype' = 'f' then 'functions'
                            when obj->>'objtype' = 'T' then 'types'
                            when obj->>'objtype' = 'n' then 'schemas'
                       end
                     , case when rec.grantee = 0 then 'public' else rec.grantee::regrole::text end
                     , case when rec.is_grantable then 'with grant option' else '' end
                     ));
      end if;
    end loop;
  end loop;

  -- schemas
  foreach obj in array schemas
  loop
    if obj->>'owner' = 'postgres' then
      execute(format('alter schema %s owner to postgres;', (obj->>'oid')::regnamespace));
    end if;
    for rec in
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode((obj->>'acl')::aclitem[])
      where grantee::regrole in ('postgres', 'supabase_admin')
    loop
      execute(format('revoke %s on schema %s from %I', rec.privilege_type, (obj->>'oid')::regnamespace, case when rec.grantee = 'postgres'::regrole then 'supabase_admin' else 'postgres' end));
    end loop;
  end loop;
  foreach obj in array schemas
  loop
    for rec in
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode((obj->>'acl')::aclitem[])
      where grantee::regrole in ('postgres', 'supabase_admin')
    loop
      execute(format('grant %s on schema %s to %s %s', rec.privilege_type, (obj->>'oid')::regnamespace, rec.grantee::regrole, case when rec.is_grantable then 'with grant option' else '' end));
    end loop;
  end loop;

  -- types
  foreach obj in array types
  loop
    if obj->>'owner' = 'postgres' then
      execute(format('alter type %s owner to postgres;', (obj->>'oid')::regtype));
    end if;
    for rec in
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode((obj->>'acl')::aclitem[])
      where grantee::regrole in ('postgres', 'supabase_admin')
    loop
      execute(format('revoke %s on type %s from %I', rec.privilege_type, (obj->>'oid')::regtype, case when rec.grantee = 'postgres'::regrole then 'supabase_admin' else 'postgres' end));
    end loop;
  end loop;
  foreach obj in array types
  loop
    for rec in
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode((obj->>'acl')::aclitem[])
      where grantee::regrole in ('postgres', 'supabase_admin')
    loop
      execute(format('grant %s on type %s to %s %s', rec.privilege_type, (obj->>'oid')::regtype, rec.grantee::regrole, case when rec.is_grantable then 'with grant option' else '' end));
    end loop;
  end loop;

  -- functions
  foreach obj in array functions
  loop
    if obj->>'owner' = 'postgres' then
      execute(format('alter routine %s(%s) owner to postgres;', (obj->>'oid')::regproc, pg_get_function_identity_arguments((obj->>'oid')::regproc)));
    end if;
    for rec in
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode((obj->>'acl')::aclitem[])
      where grantee::regrole in ('postgres', 'supabase_admin')
    loop
      execute(format('revoke %s on %s %s(%s) from %I'
          , rec.privilege_type
          , case
              when obj->>'kind' = 'p' then 'procedure'
              else 'function'
            end
          , (obj->>'oid')::regproc
          , pg_get_function_identity_arguments((obj->>'oid')::regproc)
          , case when rec.grantee = 'postgres'::regrole then 'supabase_admin' else 'postgres' end
          ));
    end loop;
  end loop;
  foreach obj in array functions
  loop
    for rec in
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode((obj->>'acl')::aclitem[])
      where grantee::regrole in ('postgres', 'supabase_admin')
    loop
      execute(format('grant %s on %s %s(%s) to %s %s'
          , rec.privilege_type
          , case
              when obj->>'kind' = 'p' then 'procedure'
              else 'function'
            end
          , (obj->>'oid')::regproc
          , pg_get_function_identity_arguments((obj->>'oid')::regproc)
          , rec.grantee::regrole
          , case when rec.is_grantable then 'with grant option' else '' end
          ));
    end loop;
  end loop;

  -- relations
  foreach obj in array relations
  loop
    -- obj->>'oid' (text) needs to be casted to oid first for some reason

    if obj->>'owner' = 'postgres' then
      execute(format('alter table %s owner to postgres;', (obj->>'oid')::oid::regclass));
    end if;
    for rec in
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode((obj->>'acl')::aclitem[])
      where grantee::regrole in ('postgres', 'supabase_admin')
    loop
      execute(format('revoke %s on table %s from %I', rec.privilege_type, (obj->>'oid')::oid::regclass, case when rec.grantee = 'postgres'::regrole then 'supabase_admin' else 'postgres' end));
    end loop;
  end loop;
  foreach obj in array relations
  loop
    -- obj->>'oid' (text) needs to be casted to oid first for some reason

    for rec in
      select grantor, grantee, privilege_type, is_grantable
      from aclexplode((obj->>'acl')::aclitem[])
      where grantee::regrole in ('postgres', 'supabase_admin')
    loop
      execute(format('grant %s on table %s to %s %s', rec.privilege_type, (obj->>'oid')::oid::regclass, rec.grantee::regrole, case when rec.is_grantable then 'with grant option' else '' end));
    end loop;
  end loop;

  if exists (select from pg_event_trigger where evtname = 'pgsodium_trg_mask_update') then
    alter event trigger pgsodium_trg_mask_update enable;
  end if;
end
$$;

do $$
begin
  if exists (select from pg_extension where extname = 'timescaledb') then
    execute(format('select %s.timescaledb_post_restore()', (select pronamespace::regnamespace from pg_proc where proname = 'timescaledb_post_restore')));
  end if;
end
$$;

alter database postgres connection limit -1;

-- #incident-2024-09-12-project-upgrades-are-temporarily-disabled
do $$
begin
  if exists (select from pg_authid where rolname = 'pg_read_all_data') then
    execute('grant pg_read_all_data to postgres');
  end if;
end
$$;
grant pg_signal_backend to postgres;

set session authorization supabase_admin;
drop role supabase_tmp;
commit;
EOSQL
}
