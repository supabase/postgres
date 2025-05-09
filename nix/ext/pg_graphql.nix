{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_12_9, cargo, rust-bin }:

let
    rustVersion = "1.81.0";
    cargo = rust-bin.stable.${rustVersion}.default;
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
    PGPORT = toString (5430 + 
      (if builtins.match ".*_.*" postgresql.version != null then 1 else 0) +  # +1 for OrioleDB
      ((builtins.fromJSON (builtins.substring 0 2 postgresql.version)) - 15) * 2);  # +2 for each major version
    RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
    NIX_BUILD_CORES = "4";  # Limit parallel jobs
    CARGO_BUILD_JOBS = "4"; # Limit cargo parallelism
  };
  CARGO_PROFILE_RELEASE_BUILD_OVERRIDE_DEBUG = true;


  doCheck = false;

  meta = with lib; {
    description = "GraphQL support for PostreSQL";
    homepage = "https://github.com/supabase/${pname}";
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
