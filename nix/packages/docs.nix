{ stdenvNoCC, python3Packages, ... }:
stdenvNoCC.mkDerivation {
  name = "docs";

  src = ../.;

  nativeBuildInputs = with python3Packages; [
    mike
    mkdocs
    mkdocs-material
    mkdocs-linkcheck
  ];

  buildPhase = ''
    mkdocs build
  '';

  installPhase = ''
    mv out $out
  '';
}
