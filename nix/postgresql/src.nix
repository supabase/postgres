{
  stdenv,
  postgresql,
  lib,
  bzip2,
}:
stdenv.mkDerivation {
  pname = "postgresql-${postgresql.version}-src";
  version = postgresql.version;

  src = postgresql.src;

  nativeBuildInputs = [ bzip2 ];

  phases = [
    "unpackPhase"
    "installPhase"
  ];

  installPhase = ''
    mkdir -p $out
    cp -r . $out
    # This tree is read later by a different, unrelated user (e.g. `postgres`
    # via /var/lib/postgresql/.nix-profile, for GDB source resolution) - make
    # sure it's readable by everyone rather than relying on whatever mode
    # bits happened to survive the tarball extraction + copy.
    chmod -R u+rwX,go+rX $out
  '';

  meta = with lib; {
    description = "PostgreSQL 15 source files";
    homepage = "https://www.postgresql.org/";
    license = licenses.postgresql;
    inherit (platforms) all;
  };
}
