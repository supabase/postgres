{
  lib,
  stdenv,
  fetchurl,
  openssl,
  libevent,
  c-ares,
  pkg-config,
  systemdLibs,
  nixosTests,
  pandoc,
  python3,
}:

let
  # Renovate updates this tag, and the workflow refreshes the hash below.
  # The Git tags look like pgbouncer_1_25_1.
  # We keep the tag here and build the version from it.
  # renovate: datasource=github-tags depName=pgbouncer packageName=pgbouncer/pgbouncer versioning=regex:^pgbouncer_(?<major>\d+)_(?<minor>\d+)_(?<patch>\d+)$
  tag = "pgbouncer_1_25_1";
in
stdenv.mkDerivation rec {
  pname = "pgbouncer";
  version = lib.replaceStrings [ "_" ] [ "." ] (lib.removePrefix "pgbouncer_" tag);

  src = fetchurl {
    url = "https://www.pgbouncer.org/downloads/files/${version}/${pname}-${version}.tar.gz";
    hash = "sha256-blZq6S/j739qG54m1gSffXyjnEDinns49tVQCuFdhGU=";
  };

  nativeBuildInputs = [
    pkg-config
    pandoc
    python3
  ];
  buildInputs = [
    libevent
    openssl
    c-ares
  ]
  ++ lib.optional stdenv.hostPlatform.isLinux systemdLibs;
  enableParallelBuilding = true;
  configureFlags = lib.optional stdenv.hostPlatform.isLinux "--with-systemd";

  passthru.tests = {
    pgbouncer = nixosTests.pgbouncer;
  };

  meta = with lib; {
    homepage = "https://www.pgbouncer.org/";
    mainProgram = "pgbouncer";
    description = "Lightweight connection pooler for PostgreSQL";
    changelog = "https://github.com/pgbouncer/pgbouncer/releases/tag/pgbouncer_${
      replaceStrings [ "." ] [ "_" ] version
    }";
    license = licenses.isc;
    platforms = platforms.all;
  };
}
