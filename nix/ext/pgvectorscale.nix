{
  lib,
  fetchFromGitHub,
  postgresql,
  buildPgrxExtension_0_12_9,
  rust-bin,
}:

let
  rustVersion = "1.84.0";
  cargo = rust-bin.stable.${rustVersion}.default;
in

buildPgrxExtension_0_12_9 rec {
  pname = "pgvectorscale";
  version = "0.8.0";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "timescale";
    repo = "pgvectorscale";
    rev = "0.8.0";
    hash = "sha256-hjQUEuc+Sj2JuWkxwha/yja6/Lf2eR32JXoVuqquYSA=";
  };

  buildAndTestSubdir = "pgvectorscale";

  nativeBuildInputs = [ cargo ];
  buildInputs = [ postgresql ];

  CARGO = "${cargo}/bin/cargo";

  cargoLock.lockFile = ./Cargo.lock;

  postUnpack = ''
    cp ${./Cargo.lock} Cargo.lock
    chmod +w Cargo.lock
    cp ${./Cargo.lock} source/Cargo.lock
    chmod +w source/Cargo.lock
    cp ${./Cargo.lock} source/pgvectorscale/Cargo.lock
    chmod +w source/pgvectorscale/Cargo.lock
  '';

  doCheck = false;

  postInstall = ''
    # Let the default PGRX install happen first
    runHook preInstall

    # Default PGRX installation
    cargo pgrx install --release --pg-config=${postgresql}/bin/pg_config

    # Now move files to correct locations
    mkdir -p $out/{lib,share/postgresql/extension}

    # Move .so files to lib directory
    find $out -name "*.so" -not -path "*/lib/*" -exec mv {} $out/lib/ \;

    # Move .control and .sql files to extension directory  
    find $out -name "*.control" -not -path "*/extension/*" -exec mv {} $out/share/postgresql/extension/ \;
    find $out -name "*.sql" -not -path "*/extension/*" -exec mv {} $out/share/postgresql/extension/ \;

    runHook postInstall
  '';

  meta = with lib; {
    description = "High-performance vector search complement to pgvector";
    homepage = "https://github.com/timescale/pgvectorscale";
    license = licenses.postgresql;
    platforms = postgresql.meta.platforms;
  };
}
