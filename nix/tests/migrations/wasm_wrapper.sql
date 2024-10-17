create extension if not exists wrappers with schema extensions;

create foreign data wrapper wasm_wrapper
  handler wasm_fdw_handler
  validator wasm_fdw_validator;

create server example_server
  foreign data wrapper wasm_wrapper
  options (
    -- change below fdw_package_* options accordingly, find examples in the README.txt in your releases
    fdw_package_url 'https://github.com/supabase-community/wasm-fdw-example/releases/download/v0.1.0/wasm_fdw_example.wasm',
    fdw_package_name 'my-company:example-fdw',
    fdw_package_version '0.1.0',
    fdw_package_checksum '67bbe7bfaebac6e8b844813121099558ffe5b9d8ac6fca8fe49c20181f50eba8',
    api_url 'https://api.github.com'
  );

create schema github;

create foreign table github.events (
  id text,
  type text,
  actor jsonb,
  repo jsonb,
  payload jsonb,
  public boolean,
  created_at timestamp
)
  server example_server
  options (
    object 'events',
    rowid_column 'id'
  );
