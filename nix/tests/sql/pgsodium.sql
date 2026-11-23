select
  status
from
  pgsodium.create_key();

set client_min_messages = warning;

create table public.pgsodium_mask_quoting (
  secret text,
  "quo""te" text,
  "dol$t$lar" text
);

security label for pgsodium on column public.pgsodium_mask_quoting.secret
  is 'ENCRYPT WITH KEY ID 00000000-0000-0000-0000-000000000000';

security label for pgsodium on column public.pgsodium_mask_quoting."quo""te"
  is 'ENCRYPT WITH KEY ID 00000000-0000-0000-0000-000000000000';

security label for pgsodium on column public.pgsodium_mask_quoting."dol$t$lar"
  is 'ENCRYPT WITH KEY ID 00000000-0000-0000-0000-000000000000';

select
  tgname,
  tgfoid::regproc
from
  pg_trigger
where
  tgrelid = 'public.pgsodium_mask_quoting'::regclass
order by
  tgname;

drop table public.pgsodium_mask_quoting cascade;

drop function public.pgsodium_mask_quoting_encrypt_secret_secret();

drop function public."pgsodium_mask_quoting_encrypt_secret_quo""te"();

drop function public."pgsodium_mask_quoting_encrypt_secret_dol$t$lar"();

reset client_min_messages;
