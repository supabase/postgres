{ lib
, stdenv
, fetchFromGitHub
, postgresql
, buildPgrxExtension_0_12_5
, rust-bin
}:

let
  rustVersion = "1.80.0";  
  rust = rust-bin.stable.${rustVersion}.default;
in

buildPgrxExtension_0_12_5 rec {
  pname = "pg_graphql";
  version = "1.5.7";
  inherit postgresql;

  # Pass the paths to cargo and rustc
  CARGO = "${rust}/bin/cargo";
  RUSTC = "${rust}/bin/rustc";

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "8e0ca67ad2ea36dbe3453e11f951c7f9faee4ecf";
    hash = "sha256-psJCauZgg9WUDd/N4PeptSnu0qp5RLziC1tYf3LbYsc=";
  };

  nativeBuildInputs = [ rust ];
  buildInputs = [ postgresql ];

  # Darwin environment variables
  env = lib.optionalAttrs stdenv.isDarwin {
    POSTGRES_LIB = "${postgresql}/lib";
    RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
    PGPORT = "5434";
  };

  cargoHash = "sha256-lkIK4c9ZTEx8/jskQJBFNK5YRwl2pPZiWJg202ayRhI=";

  # Disable tests as mentioned in the original
  doCheck = false;

  meta = with lib; {
    description = "GraphQL support for PostgreSQL";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
