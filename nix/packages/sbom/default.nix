{ pkgs, sbomnix }:
let
  sbom = pkgs.buildGoModule {
    pname = "sbom";
    version = "1.0.0";
    src = ./.;
    vendorHash = null;

    subPackages = [ "cmd/sbom" ];

    meta = with pkgs.lib; {
      description = "SPDX SBOM generator with Ubuntu and Nix support";
      license = licenses.asl20;
      mainProgram = "sbom";
    };
  };

  # Wrapper script for Ubuntu-only SBOM
  sbom-ubuntu = pkgs.writeShellScriptBin "sbom-ubuntu" ''
    ${sbom}/bin/sbom ubuntu "$@"
  '';

  # Wrapper script for Nix-only SBOM
  sbom-nix = pkgs.writeShellScriptBin "sbom-nix" ''
    export PATH="${sbomnix}/bin:$PATH"
    ${sbom}/bin/sbom nix "$@"
  '';

  # Wrapper script for merged SBOM (main entry point)
  sbom-generator = pkgs.writeShellScriptBin "sbom-generator" ''
    export PATH="${sbomnix}/bin:$PATH"
    ${sbom}/bin/sbom combined "$@"
  '';
in
{
  inherit
    sbom
    sbom-ubuntu
    sbom-nix
    sbom-generator
    sbomnix
    ;
}
