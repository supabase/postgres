{
  description = "Gatekeeper PAM";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

    gatekeeper.url = "git+ssh://git@github.com/supabase/jit-db-gatekeeper";
  };

  outputs = { self, nixpkgs, gatekeeper }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in {
      packages.x86_64-linux.default = pkgs.stdenv.mkDerivation {
        pname = "gatekeeper";
        version = "0.1.0";

        # Use lib/include from your module
        buildInputs = [ gatekeeper.packages.x86_64-linux.default ];

        src = ./.;
      };
    };
}

{ stdenv, go, gcc, pamModulePackage, ... }:

stdenv.mkDerivation {
  pname = "consumer";
  version = "0.1.0";

  buildInputs = [
    pamModulePackage   # this brings in the .so, headers, etc.
  ];

  buildPhase = ''
    echo "Building consumer project..."
    ls -lh ${pamModulePackage}/lib/security
  '';
}