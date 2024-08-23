select
  1
from
  vault.create_secret('my_s3kre3t');

select
  1
from
  vault.create_secret(
    'another_s3kre3t',
    'unique_name',
    'This is the description'
  );

insert into vault.secrets (secret)
values
  ('s3kre3t_k3y');

select
  name,
  description
from
  vault.decrypted_secrets 
order by
  created_at desc 
limit
  3;
 


