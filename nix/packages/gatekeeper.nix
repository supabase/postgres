{ pkgs, ... }:
let
  upstream-src = pkgs.fetchFromGitHub {
    owner = "supabase";
    repo = "jit-db-gatekeeper";
    rev = "v1.0.0";
    sha256 = "sha256-C4RPyzpItJrM/FxINpEIKvkYdbfaFXK0hBJe17PpejM=";
  };

  upstream-gatekeeper = pkgs.buildGoModule {
    pname = "jit-db-gatekeeper";
    version = "1.0.0";

    src = upstream-src;

    # Get vendorHash by setting to null first, building, and using error message
    vendorHash = null;

    # Environment variables - choose ONE approach
    CGO_ENABLED = "1";

    # Build flags
    ldflags = [
      "-s"
      "-w"
    ];
  };
in

pkgs.stdenv.mkDerivation {
  pname = "gatekeeper";
  version = "1.0.0";

  buildInputs = [ upstream-gatekeeper ];

  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/lib/security/
    cp ${upstream-gatekeeper}/pam_jit_pg.so $out/lib/security/
  '';
}
