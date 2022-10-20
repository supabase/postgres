
SELECT database_privs_are(
    'postgres', 'postgres', ARRAY['CONNECT', 'TEMPORARY', 'CREATE']
);
