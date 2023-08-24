-- migrate:up

create extension if not exists http with schema extensions;
create extension if not exists pg_tle;

do $do$
begin
    if not exists(select 1 from pgtle.available_extensions() where name = 'supabase-dbdev') then

        perform
            pgtle.install_extension(
                'supabase-dbdev',
                '0.0.2',
                'Install packages from the database.dev registry',
                $pkg$

        create schema dbdev;

        create or replace function dbdev.install(package_name text)
            returns bool
            language plpgsql
        as $$
        declare
            -- Endpoint
            base_url text = 'https://api.database.dev/rest/v1/';
            apikey text = 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InhtdXB0cHBsZnZpaWZyYndtbXR2Iiwicm9sZSI6ImFub24iLCJpYXQiOjE2ODAxMDczNzIsImV4cCI6MTk5NTY4MzM3Mn0.z2CN0mvO2No8wSi46Gw59DFGCTJrzM0AQKsu_5k134s';

            http_ext_schema regnamespace = extnamespace::regnamespace from pg_catalog.pg_extension where extname = 'http' limit 1;
            pgtle_is_available bool = true from pg_catalog.pg_extension where extname = 'pg_tle' limit 1;
            -- HTTP respones
            rec jsonb;
            status int;
            contents json;

            -- Install Record
            rec_sql text;
            rec_ver text;
            rec_from_ver text;
            rec_to_ver text;
            rec_package_name text;
            rec_description text;
            rec_requires text[];
        begin

            if http_ext_schema is null then
                raise exception using errcode='22000', message=format('dbdev requires the http extension and it is not available');
            end if;

            if pgtle_is_available is null then
                raise exception using errcode='22000', message=format('dbdev requires the pgtle extension and it is not available');
            end if;

            -------------------
            -- Base Versions --
            -------------------
            execute  $stmt$select row_to_json(x)
            from $stmt$ || pg_catalog.quote_ident(http_ext_schema::text) || $stmt$.http(
                (
                    'GET',
                    format(
                        '%spackage_versions?select=package_name,version,sql,control_description,control_requires&limit=50&package_name=eq.%s',
                        $stmt$ || pg_catalog.quote_literal(base_url) || $stmt$,
                        $stmt$ || pg_catalog.quote_literal($1) || $stmt$
                    ),
                    array[
                        ('apiKey', $stmt$ || pg_catalog.quote_literal(apikey) || $stmt$)::http_header
                    ],
                    null,
                    null
                )
            ) x
            limit 1; $stmt$
            into rec;

            status = (rec ->> 'status')::int;
            contents = to_json(rec ->> 'content') #>> '{}';

            if status <> 200 then
                raise notice using errcode='22000', message=format('DBDEV INFO: %s', contents);
                raise exception using errcode='22000', message=format('Non-200 response code while loading versions from dbdev');
            end if;

            if contents is null or json_typeof(contents) <> 'array' or json_array_length(contents) = 0 then
                raise exception using errcode='22000', message=format('No versions for package named named %s', package_name);
            end if;

            for rec_package_name, rec_ver, rec_sql, rec_description, rec_requires in select
                    (r ->> 'package_name'),
                    (r ->> 'version'),
                    (r ->> 'sql'),
                    (r ->> 'control_description'),
                    array(select json_array_elements_text((r -> 'control_requires')))
                from
                    json_array_elements(contents) as r
                loop

                -- Install the primary version
                if not exists (
                    select true
                    from pgtle.available_extensions()
                    where
                        name = rec_package_name
                ) then
                    perform pgtle.install_extension(rec_package_name, rec_ver, rec_package_name, rec_sql, rec_requires);
                end if;

                -- Install other available versions
                if not exists (
                    select true
                    from pgtle.available_extension_versions()
                    where
                        name = rec_package_name
                        and version = rec_ver
                ) then
                    perform pgtle.install_extension_version_sql(rec_package_name, rec_ver, rec_sql);
                end if;

            end loop;

            ----------------------
            -- Upgrade Versions --
            ----------------------
            execute  $stmt$select row_to_json(x)
            from $stmt$ || pg_catalog.quote_ident(http_ext_schema::text) || $stmt$.http(
                (
                    'GET',
                    format(
                        '%spackage_upgrades?select=package_name,from_version,to_version,sql&limit=50&package_name=eq.%s',
                        $stmt$ || pg_catalog.quote_literal(base_url) || $stmt$,
                        $stmt$ || pg_catalog.quote_literal($1) || $stmt$
                    ),
                    array[
                        ('apiKey', $stmt$ || pg_catalog.quote_literal(apikey) || $stmt$)::http_header
                    ],
                    null,
                    null
                )
            ) x
            limit 1; $stmt$
            into rec;

            status = (rec ->> 'status')::int;
            contents = to_json(rec ->> 'content') #>> '{}';

            if status <> 200 then
                raise notice using errcode='22000', message=format('DBDEV INFO: %s', contents);
                raise exception using errcode='22000', message=format('Non-200 response code while loading upgrade pathes from dbdev');
            end if;

            if json_typeof(contents) <> 'array' then
                raise exception using errcode='22000', message=format('Invalid response from dbdev upgrade pathes');
            end if;

            for rec_package_name, rec_from_ver, rec_to_ver, rec_sql in select
                    (r ->> 'package_name'),
                    (r ->> 'from_version'),
                    (r ->> 'to_version'),
                    (r ->> 'sql')
                from
                    json_array_elements(contents) as r
                loop

                if not exists (
                    select true
                    from pgtle.extension_update_paths(rec_package_name)
                    where
                        source = rec_from_ver
                        and target = rec_to_ver
                        and path is not null
                ) then
                    perform pgtle.install_update_path(rec_package_name, rec_from_ver, rec_to_ver, rec_sql);
                end if;
            end loop;

            --------------------------
            -- Send Download Notice --
            --------------------------
            -- Notifies dbdev that a package has been downloaded and records IP + user agent so we can compute unique download counts
            execute  $stmt$select row_to_json(x)
            from $stmt$ || pg_catalog.quote_ident(http_ext_schema::text) || $stmt$.http(
                (
                    'POST',
                    format(
                        '%srpc/register_download',
                        $stmt$ || pg_catalog.quote_literal(base_url) || $stmt$
                    ),
                    array[
                        ('apiKey', $stmt$ || pg_catalog.quote_literal(apikey) || $stmt$)::http_header,
                        ('x-client-info', 'dbdev/0.0.2')::http_header
                    ],
                    'application/json',
                    json_build_object('package_name', $stmt$ || pg_catalog.quote_literal($1) || $stmt$)::text
                )
            ) x
            limit 1; $stmt$
            into rec;

            return true;
        end;
        $$;

        $pkg$

        );
        
    end if;
end$do$;

create extension if not exists "supabase-dbdev";

-- migrate:down
