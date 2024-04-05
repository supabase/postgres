{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_10_2 }:

buildPgrxExtension_0_10_2 rec {
  pname = "pg_jsonschema";
  version = "0.2.0";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-57gZbUVi8P4EB8T0P19JBVXcetQcr6IxuIx96NNFA/0=";
  };

  cargoHash = "sha256-XMKZUdubCwPDnrv6yao7GaavoRK6cVyy1WqFBQ6wh3s=";

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
