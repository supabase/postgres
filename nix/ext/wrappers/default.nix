{ lib
, stdenv
, fetchFromGitHub
, openssl
, pkg-config
, postgresql
, buildPgrxExtension_0_11_3
, cargo
}:

buildPgrxExtension_0_11_3 rec {
  pname = "supabase-wrappers";
  version = "0.3.1";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = "wrappers";
    rev = "v${version}";
    hash = "sha256-ZwTw0USJC/F/ZW5usX7p0CB8p2YzeUb6OLiMF3D1+J4=";
  };

  nativeBuildInputs = [ pkg-config cargo ];

  buildInputs = [ openssl ];

  # Needed to get openssl-sys to use pkg-config.
  OPENSSL_NO_VENDOR = 1;
  
  CARGO="${cargo}/bin/cargo";

  cargoLock = {
    #TODO when we move to newer versions this lockfile will need to be sourced
    # from ${src}/Cargo.lock
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      "clickhouse-rs-1.0.0-alpha.1" = "sha256-0zmoUo/GLyCKDLkpBsnLAyGs1xz6cubJhn+eVqMEMaw=";
    };
  };
  postPatch = "cp ${cargoLock.lockFile} Cargo.lock";

  buildAndTestSubdir = "wrappers";
  buildFeatures = [
    "helloworld_fdw"
    "bigquery_fdw"
    "clickhouse_fdw"
    "stripe_fdw"
    "firebase_fdw"
    "s3_fdw"
    "airtable_fdw"
    "logflare_fdw"
  ];

  # FIXME (aseipp): disable the tests since they try to install .control
  # files into the wrong spot, aside from that the one main test seems
  # to work, though
  doCheck = false;

  meta = with lib; {
    description = "Various Foreign Data Wrappers (FDWs) for PostreSQL";
    homepage = "https://github.com/supabase/wrappers";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
