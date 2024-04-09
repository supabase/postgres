{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_11_2 }:

buildPgrxExtension_0_11_2 rec {
  pname = "pg_graphql";
  version = "1.5.1";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-cAiD2iSFmZwC+Zy0x+MABseWCxXRtRY74Dj0oBKet+o=";
  };

  cargoHash = "sha256-BOw4SafWD8z2Oj8KPVv7GQEOQ1TCShhcG7XmQiM9W68=";

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
