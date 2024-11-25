{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_12_6, cargo, rust-bin }:
let
  rustVersion = "1.80.0";
  cargo = rust-bin.stable.${rustVersion}.default;
in
buildPgrxExtension_0_12_6 rec {
  pname = "pg_graphql";
  version = "1.5.9";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-YpLN43FtLhp2cb7cyM+4gEx8GTwsRiKTfxaMq0b8hk0=";
  };

  nativeBuildInputs = [ cargo ];
  buildInputs = [ postgresql ];
  
  CARGO="${cargo}/bin/cargo";
  #darwin env needs PGPORT to be unique for build to not clash with other pgrx extensions
  env = lib.optionalAttrs stdenv.isDarwin {
    POSTGRES_LIB = "${postgresql}/lib";
    RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
    PGPORT = "5434";
  };
  cargoHash = "sha256-d2RSHtJgbYlOvArjOTaeYoca01UyWPUEO5vhktxxB6U=";

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
