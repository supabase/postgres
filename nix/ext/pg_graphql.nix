{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_11_3, cargo }:

buildPgrxExtension_0_11_3 rec {
  pname = "pg_graphql";
  version = "1.5.1";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "samrose";
    repo = pname;
    rev = "sam/update-pgrx";
    hash = "sha256-8HM4g7ylBVlPzjr8bBfEM1smK2xRGD040EdfLFhlLRo=";
  };

  nativeBuildInputs = [ cargo ];
  CARGO="${cargo}/bin/cargo";
  cargoHash = "sha256-E5dMTfFrjZ5ghpr7KEzdBuDvnF+mVjmwMT3CcHQylN4=";

  # FIXME (aseipp): disable the tests since they try to install .control
  # files into the wrong spot, aside from that the one main test seems
  # to work, though
  doCheck = false;

  meta = with lib; {
    description = "GraphQL support for PostreSQL";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
