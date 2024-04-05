{ lib, stdenv, fetchFromGitHub, postgresql }:

let
  # NOTE (aseipp): the 1.x series of pg_stat_monitor has some non-standard and
  # weird build logic (Percona projects in general seem to have their own
  # strange build harness) where it will try to pick the right .sql file to
  # install into the extension dir based on the postgresql major version. for
  # our purposes, we only need to support v13 and v14+, so just replicate this
  # logic from the makefile and pick the right file here.
  #
  # this seems to all be cleaned up in version 2.0 of the extension, so ideally
  # we could upgrade to it later on and nuke this.
  # DEPRECATED sqlFilename = if lib.versionOlder postgresql.version "14"
  #   then "pg_stat_monitor--1.0.13.sql.in"
  #   else "pg_stat_monitor--1.0.14.sql.in";

in
stdenv.mkDerivation rec {
  pname = "pg_stat_monitor";
  version = "1.1.1";

  buildInputs = [ postgresql ];

  src = fetchFromGitHub {
    owner = "percona";
    repo = pname;
    rev = "refs/tags/${version}";
    hash = "sha256-S4N4Xnbkz57ue6f/eGjuRi64xT0NXjpMJiNNZnbbvbU=";
  };

  makeFlags = [ "USE_PGXS=1" ];

  installPhase = ''
    mkdir -p $out/{lib,share/postgresql/extension}
  
    cp pg_stat_monitor--1.0.15.sql.in pg_stat_monitor--1.0.sql
  
    cp *.so      $out/lib
    cp *.sql     $out/share/postgresql/extension
    cp *.control $out/share/postgresql/extension
  '';

  meta = with lib; {
    description = "Query Performance Monitoring Tool for PostgreSQL";
    homepage = "https://github.com/percona/${pname}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
    broken = lib.versionOlder postgresql.version "15";
  };
}
