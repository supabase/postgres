{ pkgs, ... }:
pkgs.buildGoModule {
  pname = "jit-db-gatekeeper";
  version = "1.0.6";
  src = pkgs.fetchFromGitHub {
    owner = "supabase";
    repo = "jit-db-gatekeeper";
    rev = "v1.0.6";
    sha256 = "sha256-/m34Fl08PyRRIwi1eYkLUQWy+5V87sfE65HjEbVjFSs=";
  };
  vendorHash = null;

  buildInputs = [ pkgs.pam ];

  # dlopen'd into PAM, which already links these libs
  NIX_DONT_SET_RPATH = pkgs.stdenv.isLinux;

  buildPhase = ''
    runHook preBuild
    go build -buildmode=c-shared -o pam_jit_pg.so
    runHook postBuild
  '';

  installPhase = ''
    runHook preInstall
    mkdir -p $out/lib/security
    cp pam_jit_pg.so $out/lib/security/
    runHook postInstall
  '';
}
