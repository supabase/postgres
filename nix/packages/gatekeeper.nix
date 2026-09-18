{ pkgs, ... }:
let

  go124 = pkgs.go_1_24;
  buildGoModule124 = pkgs.buildGoModule.override { go = go124; };

  upstream-gatekeeper = buildGoModule124 {
    pname = "jit-db-gatekeeper";
    version = "1.0.5";
    src = pkgs.fetchFromGitHub {
      owner = "supabase";
      repo = "jit-db-gatekeeper";
      rev = "v1.0.5";
      sha256 = "sha256-z+TE9Cc+NL6nvCIkAKFdSgm4V/1K45tRRnfQdauDjes=";
    };
    vendorHash = null;

    buildInputs = [ pkgs.pam ];
    NIX_DONT_SET_RPATH = true;

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
  version = "1.0.5";

  buildInputs = [ upstream-gatekeeper ];
  nativeBuildInputs = [ pkgs.patchelf ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/lib/security/
    cp ${upstream-gatekeeper}/lib/security/pam_jit_pg.so $out/lib/security/pam_jit_pg.so
    chmod +w $out/lib/security/pam_jit_pg.so
    so=$out/lib/security/pam_jit_pg.so
    rp=$(patchelf --print-rpath "$so")
    patchelf --remove-rpath "$so"
    if [ -n "$rp" ]; then
      off=$(grep -aboF "$rp" "$so" | head -1 | cut -d: -f1)
      dd if=/dev/zero of="$so" bs=1 seek="$off" count="''${#rp}" conv=notrunc status=none
    fi
  '';
}
