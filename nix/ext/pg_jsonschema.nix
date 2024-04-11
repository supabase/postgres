{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_11_3, cargo }:

buildPgrxExtension_0_11_3 rec {
  pname = "pg_jsonschema";
  version = "0.3.1";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-YdKpOEiDIz60xE7C+EzpYjBcH0HabnDbtZl23CYls6g=";
  };

  nativeBuildInputs = [ cargo ];
  
  CARGO="${cargo}/bin/cargo";


  cargoHash = "sha256-VcS+efMDppofuFW2zNrhhsbC28By3lYekDFquHPta2g=";

  # FIXME (aseipp): testsuite tries to write files into /nix/store; we'll have
  # to fix this a bit later.
  doCheck = false;

  meta = with lib; {
    description = "JSON Schema Validation for PostgreSQL";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
