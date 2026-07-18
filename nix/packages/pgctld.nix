{
  lib,
  buildGoModule,
  multigres-src,
}:
buildGoModule {
  pname = "pgctld";
  version = multigres-src.rev;
  src = multigres-src;
  subPackages = [ "go/cmd/pgctld" ];
  env.CGO_ENABLED = "0";
  ldflags = [ ];
  # The Makefile copies pico CSS assets before go build; pgctld does not use web
  # templates so this is a no-op, but kept for safety in case of future imports.
  preBuild = ''
    cp external/pico/pico.* go/common/web/templates/css/ 2>/dev/null || true
  '';
  # Tests require a running PostgreSQL instance (integration tests); skip in sandbox.
  doCheck = false;
  vendorHash = "sha256-lObK/Oukh1oEPQENlhny8eNxRhSlTKywO3GCGZ8u5Qw=";

  meta = {
    description = "PostgreSQL control daemon for Multigres cluster lifecycle management";
    mainProgram = "pgctld";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
  };
}
