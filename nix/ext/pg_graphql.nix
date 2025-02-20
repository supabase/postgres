{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_12_9, cargo, rust-bin }:

let
    rustVersion = "nightly";
    cargo = rust-bin.nightly.latest.default;
in
buildPgrxExtension_0_12_9 rec {
  pname = "pg_graphql";
  version = "1.5.11";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-BMZc9ui+2J3U24HzZZVCU5+KWhz+5qeUsRGeptiqbek=";
  };

  nativeBuildInputs = [ cargo ];
  buildInputs = [ postgresql ];
  
  CARGO = "${cargo}/bin/cargo";
  
  cargoLock = {
    lockFile = "${src}/Cargo.lock";
  };
  # Setting RUSTFLAGS in env to ensure it's available for all phases
  env = lib.optionalAttrs stdenv.isDarwin {
    POSTGRES_LIB = "${postgresql}/lib";
    PGPORT = "5434";
    RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
    NIX_BUILD_CORES = "4";  # Limit parallel jobs
    CARGO_BUILD_JOBS = "4"; # Limit cargo parallelism
  };
CARGO_BUILD_RUSTFLAGS = "--cfg tokio_unstable -C debuginfo=0";
  CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_DEBUG = true;

  
  doCheck = false;

  meta = with lib; {
    description = "GraphQL support for PostreSQL";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}