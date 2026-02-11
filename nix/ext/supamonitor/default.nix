{
  lib,
  stdenv,
  fetchurl,
  postgresql,
}:
let
  pname = "supamonitor";
  version = "0.0.4";
  pgMajor = lib.versions.major postgresql.version;

  allVersions = (builtins.fromJSON (builtins.readFile ../versions.json)).${pname};
  versionData = allVersions.${version};
  hash = versionData.hashes.${pgMajor};

  src = fetchurl {
    url = "https://github.com/supabase/${pname}/releases/download/v${version}/${pname}-v${version}-pg${pgMajor}-arm64-linux-gnu.so";
    sha256 = hash;
  };
in
stdenv.mkDerivation {
  inherit pname version src;

  dontUnpack = true;

  installPhase = ''
    install -D $src $out/lib/${pname}${postgresql.dlSuffix}
  '';

  passthru = {
    inherit pname;
    versions = [ version ];
    numberOfVersions = 1;
    inherit version;
  };

  meta = with lib; {
    description = "Supabase monitoring extension for PostgreSQL";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ soedirgo ];
    platforms = [ "aarch64-linux" ];
    license = licenses.postgresql;
  };
}
