{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_11_3, cargo }:

buildPgrxExtension_0_11_3 rec {
  pname = "pg_graphql";
  version = "1.5.2";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "b0032a5ad04eb583a3623e012a03615add68b4e4";
    hash = "sha256-npza6cGKyUyufabaUcGzV3knNa7vhR+xbZeaZy5CJ8c= ";
  };

  nativeBuildInputs = [ cargo ];
  
  CARGO="${cargo}/bin/cargo";
  
  cargoHash = "sha256-9XyUJsYptP0KanMJDAzQ4rFSN1vqZnyUdFBPQf6ryS4=";

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
