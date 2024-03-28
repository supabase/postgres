{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension }:

buildPgrxExtension rec {
  pname = "pg_jsonschema";
  version = "unstable-v0.3.0";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "v0.3.0";
    hash = "sha256-am6Ye+pOoAsOr9L4vJXw4iIOJ9x0VkUjqH6PdXMUZrk=";
  };

  cargoHash = "sha256-tiiWzu/mTKL5ruvWn6IxrXVhVqS4LXzjfacdFT9rbOY=";

  # FIXME (aseipp): testsuite tries to write files into /nix/store; we'll have
  # to fix this a bit later.
  doCheck = false;

  meta = with lib; {
    description = "JSON Schema Validation for PostgreSQL";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
