{ nix2container, system }:
let
  arch = if system == "x86_64-linux" then "amd64" else "arm64";
  hashes = {
    amd64 = "sha256-gbZeiC4j9tbKcBY8PDYZxSG9IVhselwEWDuMG9DH650=";
    arm64 = "sha256-HP+/whN55n2/hKs0ROHFVSNxNqUEpC3Y7GN84/YvKt4=";
  };
in
nix2container.pullImage {
  imageName = "docker.io/library/ubuntu";
  # Ubuntu Noble (24.04) base image
  imageDigest = "sha256:c35e29c9450151419d9448b0fd75374fec4fff364a27f176fb458d472dfc9e54";
  sha256 = hashes.${arch};
  inherit arch;
}
