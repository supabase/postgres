{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_11_3, cargo }:

buildPgrxExtension_0_11_3 rec {
  pname = "pg_graphql";
  version = "1.5.7";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-Q6XfcTKVOjo5pGy8QACc4QCHolKxEGU8e0TTC6Zg8go=";
  };

  nativeBuildInputs = [ cargo ];
  buildInputs = [ postgresql ];
  
  CARGO="${cargo}/bin/cargo";
  env = lib.optionalAttrs stdenv.isDarwin {
    POSTGRES_LIB = "${postgresql}/lib";
    RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
  };
  cargoHash = "sha256-WkHufMw8OvinMRYd06ZJACnVvY9OLi069nCgq3LSmMY=";

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
