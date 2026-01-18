{ pkgs, ... }:
let

  go124 = pkgs.go_1_24;
  buildGoModule124 = pkgs.buildGoModule.override { go = go124; };

  upstream-gatekeeper = buildGoModule124 {
    pname = "jit-db-gatekeeper";
    version = "1.0.1";
    src = pkgs.fetchFromGitHub {
      owner = "supabase";
      repo = "jit-db-gatekeeper";
      rev = "v1.0.1";
      sha256 = "sha256-4xSqQnuBYPZU6kl2LVnZbCBLCPUMKyZkezq2mPYox6k";
    };
    vendorHash = null;

    buildInputs = [ pkgs.pam ];

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
  };
in

pkgs.stdenv.mkDerivation {
  pname = "gatekeeper";
  version = "1.0.1";

  buildInputs = [ upstream-gatekeeper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/lib/security/
    cp ${upstream-gatekeeper}/lib/security/pam_jit_pg.so $out/lib/security/pam_jit_pg.so
  '';
}
