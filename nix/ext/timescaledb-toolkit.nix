{ lib, stdenv, fetchurl, postgresql, dpkg, patchelf, glibc }:

stdenv.mkDerivation rec {
  pname = "timescaledb-toolkit";
  version = "1.21.0";

  # Use the official TimescaleDB toolkit package for PostgreSQL 17
  src = fetchurl {
    url = "https://packagecloud.io/timescale/timescaledb/packages/ubuntu/jammy/timescaledb-toolkit-postgresql-17_${version}~ubuntu22.04_amd64.deb/download";
    sha256 = "12l8pngxa6vw7vkgngyyyx5gk151iay6js2smi8wkrwwscx80hjd";
  };

  nativeBuildInputs = [ dpkg patchelf ];
  buildInputs = [ postgresql glibc ];

  unpackPhase = ''
    runHook preUnpack
    dpkg-deb -x $src .
    runHook postUnpack
  '';

  installPhase = ''
    runHook preInstall
    
    # Create output directories
    mkdir -p $out/lib
    mkdir -p $out/share/postgresql/extension
    
    # Copy the shared library
    if [ -f usr/lib/postgresql/17/lib/timescaledb_toolkit-*.so ]; then
      cp usr/lib/postgresql/17/lib/timescaledb_toolkit-*.so $out/lib/
    fi
    
    # Copy extension files
    if [ -d usr/share/postgresql/17/extension ]; then
      cp -r usr/share/postgresql/17/extension/* $out/share/postgresql/extension/
    fi
    
    runHook postInstall
  '';

  postFixup = ''
    # Fix the RPATH for the shared library
    for lib in $out/lib/*.so; do
      if [ -f "$lib" ]; then
        patchelf --set-rpath "${lib.makeLibraryPath [ postgresql glibc ]}" "$lib" || true
      fi
    done
  '' + lib.optionalString (!stdenv.isDarwin) ''
    # Additional fixup for Linux
    for lib in $out/lib/*.so; do
      if [ -f "$lib" ]; then
        patchelf --set-interpreter "$(cat $NIX_CC/nix-support/dynamic-linker)" "$lib" 2>/dev/null || true
      fi
    done
  '';

  meta = with lib; {
    description = "Extension for more hyperfunctions, fully compatible with TimescaleDB and PostgreSQL";
    homepage = "https://github.com/timescale/timescaledb-toolkit";
    license = licenses.asl20;
    platforms = postgresql.meta.platforms;
    maintainers = with maintainers; [ ];
  };
}