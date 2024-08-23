create schema v;

-- create a function to perform some JavaScript operations
create function v.multiply_numbers(a integer, b integer)
  returns integer
  language plv8
as $$
  return a * b;
$$;

select
  v.multiply_numbers(3, 4);

drop schema v cascade;
