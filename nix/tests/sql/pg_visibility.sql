-- can create the extension
set role postgres;
drop extension if exists pg_visibility;
create extension pg_visibility;
reset role;
