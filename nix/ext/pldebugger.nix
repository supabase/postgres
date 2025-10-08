{
  lib,
  stdenv,
  fetchFromGitHub,
  libkrb5,
  openssl,
  postgresql,
  postgresqlTestHook,
}:

stdenv.mkDerivation rec {
  pname = "pldebugger";
  version = "1.9";

  src = fetchFromGitHub {
    owner = "EnterpriseDB";
    repo = "pldebugger";
    rev = "v${version}";
    hash = "sha256-1q/kAn0i6KdWJNcIsE2HJp9m6/TMANWXZkUMWVgpKz8=";
  };

  buildInputs = [
    libkrb5
    openssl
    postgresql
  ];

  makeFlags = [ "USE_PGXS=1" ];

  installPhase = ''
    install -D -t $out/lib plugin_debugger${postgresql.dlSuffix}
    install -D -t $out/share/postgresql/extension *.sql
    install -D -t $out/share/postgresql/extension *.control
  '';

  passthru.tests.extension = stdenv.mkDerivation {
    name = "pldebugger-test";
    dontUnpack = true;
    doCheck = true;
    buildInputs = [ postgresqlTestHook ];
    nativeCheckInputs = [ (postgresql.withPackages (ps: [ ps.pldebugger ])) ];
    postgresqlTestUserOptions = "LOGIN SUPERUSER";
    failureHook = "postgresqlStop";
    checkPhase = ''
      runHook preCheck
      psql -a -v ON_ERROR_STOP=1 -c "CREATE EXTENSION pldbgapi;"
      psql -a -v ON_ERROR_STOP=1 -c "SELECT extname, extversion FROM pg_extension WHERE extname = 'pldbgapi';"
      runHook postCheck
    '';
    installPhase = "touch $out";
  };

  meta = with lib; {
    description = "PL/pgSQL debugger API for PostgreSQL";
    homepage = "https://github.com/EnterpriseDB/pldebugger";
    changelog = "https://github.com/EnterpriseDB/pldebugger/releases/tag/v${version}";
    platforms = postgresql.meta.platforms;
    license = licenses.artistic2;
    maintainers = [ ];
  };
}