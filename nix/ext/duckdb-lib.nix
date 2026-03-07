{
  lib,
  stdenv,
  fetchFromGitHub,
  cmake,
  ninja,
  openssl,
  python3,
}:

stdenv.mkDerivation (finalAttrs: {
  pname = "duckdb";
  version = "1.4.3";

  src = fetchFromGitHub {
    owner = "duckdb";
    repo = "duckdb";
    rev = "v${finalAttrs.version}";
    hash = "sha256-zYiyY/8mYCyKuSQYNxepGbZPVgdCgULLmhZlWAAW0QA=";
  };

  outputs = [
    "out"
    "lib"
    "dev"
  ];

  # cmake installs the shared library and headers; nothing goes into $out
  # since BUILD_SHELL=OFF (no CLI binary). We create $out explicitly so
  # nixpkgs's multi-output setup hooks have a valid fallback for outputBin,
  # outputDoc, outputMan, outputInfo, etc.
  postInstall = ''
    mkdir -p $out
  '';

  nativeBuildInputs = [
    cmake
    ninja
    # python3 is required by DuckDB's cmake build scripts for code generation
    python3
  ];

  buildInputs = [ openssl ];

  cmakeFlags = [
    # Required by pg_duckdb so that DuckDB symbols are visible when loaded
    # by PostgreSQL's dlopen. Without this, pg_duckdb's .so cannot resolve
    # DuckDB symbols at runtime.
    "-DCXX_EXTRA=-fvisibility=default"
    (lib.cmakeBool "BUILD_SHELL" false)
    (lib.cmakeBool "BUILD_PYTHON" false)
    (lib.cmakeBool "BUILD_UNITTESTS" false)
    # Prevent cmake from trying to fetch anything from the internet
    (lib.cmakeBool "FETCHCONTENT_FULLY_DISCONNECTED" true)
    # Embed the version string so DuckDB doesn't report "unknown"
    (lib.cmakeFeature "OVERRIDE_GIT_DESCRIBE" "v${finalAttrs.version}-0-g0000000")
  ];

  # Skip the test suite — we just want the library
  doInstallCheck = false;
  doCheck = false;

  meta = {
    description = "DuckDB shared library (for use by pg_duckdb)";
    homepage = "https://duckdb.org/";
    license = lib.licenses.mit;
    platforms = lib.platforms.unix;
  };
})
