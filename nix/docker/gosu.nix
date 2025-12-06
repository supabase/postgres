{ pkgs, system }:
let
  version = "1.16";
  arch = if system == "x86_64-linux" then "amd64" else "arm64";
  hashes = {
    amd64 = "04ygchf66azbl54cz11ff18a5x3bwbyhpgnbn3bpv7hg8g3iykis";
    arm64 = "19mns8ihyv7i5xrpx7sm3zz4gfkzyn1zhfyyazid4ijjgn84kyi3";
  };
in
pkgs.stdenv.mkDerivation {
  pname = "gosu";
  inherit version;

  src = pkgs.fetchurl {
    url = "https://github.com/tianon/gosu/releases/download/${version}/gosu-${arch}";
    sha256 = hashes.${arch};
  };

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/usr/local/bin
    cp $src $out/usr/local/bin/gosu
    chmod +x $out/usr/local/bin/gosu
  '';
}
