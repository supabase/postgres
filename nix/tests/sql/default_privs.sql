-- this tests the outcome of doing ALTER DEFAULT PRIVILEGES..
select defaclrole::regrole, defaclnamespace::regnamespace, defaclobjtype from pg_default_acl where defaclnamespace = 'public'::regnamespace::oid order by defaclrole::regrole, defaclobjtype;
