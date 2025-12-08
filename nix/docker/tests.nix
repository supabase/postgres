# Docker image build verification tests (sandboxed, no Docker daemon required)
# For runtime tests, use: nix run .#test-docker-postgres-{15,17,orioledb-17}
{
  pkgs,
  lib,
  self',
  system,
}:
let
  # Build verification - just ensures the image builds successfully
  makeBuildCheck =
    { variant }:
    let
      image = self'.packages."docker/postgres-${variant}";
    in
    pkgs.runCommand "docker-build-check-postgres-${variant}" { } ''
      echo "Verifying Docker image build for postgres-${variant}..."

      # Check that the image JSON exists and is valid
      if [ ! -f "${image}" ]; then
        echo "ERROR: Image manifest not found at ${image}"
        exit 1
      fi

      # Verify it's valid JSON with expected fields
      ${pkgs.jq}/bin/jq -e '.version' "${image}" > /dev/null || {
        echo "ERROR: Invalid image manifest - missing version field"
        exit 1
      }

      ${pkgs.jq}/bin/jq -e '."image-config".Entrypoint' "${image}" > /dev/null || {
        echo "ERROR: Invalid image manifest - missing Entrypoint"
        exit 1
      }

      ${pkgs.jq}/bin/jq -e '."image-config".Env' "${image}" > /dev/null || {
        echo "ERROR: Invalid image manifest - missing Env"
        exit 1
      }

      echo "Image manifest validation passed!"
      echo "Image: ${image}"
      echo ""
      echo "Image config:"
      ${pkgs.jq}/bin/jq '."image-config"' "${image}"

      mkdir -p $out
      echo "Build check passed for postgres-${variant}" > $out/result.txt
      cp "${image}" $out/image-manifest.json
    '';
in
lib.optionalAttrs (system == "aarch64-linux" || system == "x86_64-linux") {
  "docker-build-postgres-15" = makeBuildCheck { variant = "15"; };
  "docker-build-postgres-17" = makeBuildCheck { variant = "17"; };
  "docker-build-postgres-orioledb-17" = makeBuildCheck { variant = "orioledb-17"; };
}
