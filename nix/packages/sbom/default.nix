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

  # Script to collect nix store paths from all user profile manifests
  collect-nix-paths = pkgs.writeShellScriptBin "collect-nix-paths" ''
    set -euo pipefail
    USERS="adminapi envoy gotrue kong nginx pgbouncer postgres postgrest supabase-admin-agent ubuntu wal-g"
    for user in $USERS; do
      manifest="/home/$user/.nix-profile/manifest.json"
      if [ -f "$manifest" ]; then
        ${pkgs.jq}/bin/jq -r '.elements | to_entries[].value.storePaths[]' "$manifest" 2>/dev/null || true
      fi
    done | sort -u | grep -v '^$'
  '';
in
{
  inherit
    sbom
    sbom-ubuntu
    sbom-nix
    sbom-generator
    collect-nix-paths
    sbomnix
    ;
}
