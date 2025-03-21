{ lib, stdenv, fetchFromGitLab, cgal, cmake, pkg-config, gmp, mpfr, boost }:

stdenv.mkDerivation rec {
  pname = "sfcgal";
  version = "61f3b08ade49493b56c6bafa98c7c1f84addbc10";

  src = fetchFromGitLab {
    owner = "sfcgal";
    repo = "SFCGAL";
    rev = "${version}";
    hash = "sha256-nKSqiFyMkZAYptIeShb1zFg9lYSny3kcGJfxdeTFqxw=";
  };

  nativeBuildInputs = [ cmake pkg-config cgal gmp mpfr boost ];

  cmakeFlags = [ "-DCGAL_DIR=${cgal}" "-DCMAKE_PREFIX_PATH=${cgal}" ];


  postPatch = ''
    substituteInPlace sfcgal.pc.in \
      --replace '$'{prefix}/@CMAKE_INSTALL_LIBDIR@ @CMAKE_INSTALL_FULL_LIBDIR@
  '';

  meta = with lib; {
    description = "A wrapper around CGAL that intents to implement 2D and 3D operations on OGC standards models";
    homepage = "https://sfcgal.gitlab.io/SFCGAL/";
    license = with licenses; [ gpl3Plus lgpl3Plus];
    platforms = platforms.all;
  };
}
