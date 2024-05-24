{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_11_3, cargo }:

buildPgrxExtension_0_11_3 rec {
  pname = "pg_graphql";
  version = "1.5.4";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-419RVol44akUFZ/0B97VjAXCUrWcKFDAFuVjvJnbkP4=";
  };

  patches = if stdenv.isDarwin then [ ./0001-pg_graphql_darwin.patch ] else [];

  nativeBuildInputs = [ cargo ] 
  ++ lib.optionals stdenv.isDarwin [];


  CARGO="${cargo}/bin/cargo";

  cargoHash = "sha256-MtgqbGPpL/VkJ7NlrIpaktJAFQLP51Ls/nMbCMe++l4=";

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
