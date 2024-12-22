{ lib, stdenv, fetchFromGitHub, libkrb5, openssl, postgresql }:
#adapted from https://github.com/NixOS/nixpkgs/blob/master/pkgs/servers/sql/postgresql/ext/pgaudit.nix
let
  source = {
    "17" = {
      version = "17.0";
      hash = "sha256-3ksq09wiudQPuBQI3dhEQi8IkXKLVIsPFgBnwLiicro=";
    };
    "16" = {
      version = "16.0";
      hash = "sha256-8+tGOl1U5y9Zgu+9O5UDDE4bec4B0JC/BQ6GLhHzQzc=";
    };
    "15" = {
      version = "1.7.0";
      hash = "sha256-8pShPr4HJaJQPjW1iPJIpj3CutTx8Tgr+rOqoXtgCcw=";
    };
  }.${lib.versions.major postgresql.version} or (throw "Source for pgaudit is not available for ${postgresql.version}");
in
stdenv.mkDerivation {
  pname = "pgaudit";
  inherit (source) version;

  src = fetchFromGitHub {
    owner = "pgaudit";
    repo = "pgaudit";
    rev = source.version;
    hash = source.hash;
  };

  buildInputs = [ libkrb5 openssl postgresql ];

  makeFlags = [ "USE_PGXS=1" ];

  installPhase = ''
    install -D -t $out/lib pgaudit${postgresql.dlSuffix}
    install -D -t $out/share/postgresql/extension *.sql
    install -D -t $out/share/postgresql/extension *.control
  '';

  meta = with lib; {
    description = "Open Source PostgreSQL Audit Logging";
    homepage = "https://github.com/pgaudit/pgaudit";
    changelog = "https://github.com/pgaudit/pgaudit/releases/tag/${source.version}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
