{ pkgs }:
pkgs.stdenv.mkDerivation {
  pname = "docker-entrypoint";
  version = "17-bullseye";

  src = pkgs.fetchurl {
    url = "https://github.com/docker-library/postgres/raw/889f9447cd2dfe21cccfbe9bb7945e3b037e02d8/17/bullseye/docker-entrypoint.sh";
    sha256 = "19b51vlqbhj1njk8knf9i53bqhaggz2fdhnjn1ln5102zyq15s8y";
  };

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/usr/local/bin
    cp $src $out/usr/local/bin/docker-entrypoint.sh
    chmod +x $out/usr/local/bin/docker-entrypoint.sh
  '';
}
