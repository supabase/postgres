{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension }:

buildPgrxExtension rec {
  pname = "pg_graphql";
  version = "unstable-1.5.0";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "v1.5.0";
    hash = "sha256-28ANRZyF22qF2YAxNAAkPfGOM3+xiO6IHdXsTp0CTQE=";
  };

  cargoHash = "sha256-CUiGs0m9aUeqjpdPyOSjz91cP7TT6kjJqnw7ImGnQuo=";

  # FIXME (aseipp): disable the tests since they try to install .control
  # files into the wrong spot, aside from that the one main test seems
  # to work, though
  doCheck = false;

  meta = with lib; {
    description = "GraphQL support for PostreSQL";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ thoughtpolice ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
