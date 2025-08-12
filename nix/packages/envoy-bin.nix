{
  envoy-bin,
  fetchurl,
  stdenv,
  ...
}:
let
  version = "1.28.0";
  inherit (stdenv.hostPlatform) system;
  throwSystem = throw "envoy-bin is not available for ${system}.";
  plat =
    {
      aarch64-linux = "aarch_64";
      x86_64-linux = "x86_64";
    }
    .${system} or throwSystem;
  hash =
    {
      aarch64-linux = "sha256-65MOMqtVVWQ+CdEdSQ45LQp5DFqA6wsOussQRr27EU0=";
      x86_64-linux = "sha256-JjlWPOm8CbHua9RzF2C1lsjtHkdM3YPMnfk2RRbhQ2c=";
    }
    .${system} or throwSystem;
in
envoy-bin.overrideAttrs {
  inherit version;
  src = fetchurl {
    url = "https://github.com/envoyproxy/envoy/releases/download/v${version}/envoy-${version}-linux-${plat}";
    inherit hash;
  };
}
