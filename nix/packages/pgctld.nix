{ lib, buildGoModule, multigres-src }:
buildGoModule {
  pname = "pgctld";
  version = "0.1.0";
  src = multigres-src;
  subPackages = [ "go/cmd/pgctld" ];
  env.CGO_ENABLED = "0";
  ldflags = [
    "-w"
    "-s"
  ];
  preBuild = ''
    cp external/pico/pico.* go/common/web/templates/css/ 2>/dev/null || true
  '';
  vendorHash = "sha256-0G/l5MlEnyXSoElPbRkn1MaQNCtil3rE/tPZILbhKaA=";
}
