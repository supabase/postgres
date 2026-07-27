{
  lib,
  buildGoModule,
  go_1_26,
  multigres-src,
}:
(buildGoModule.override { go = go_1_26; }) {
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
  vendorHash = "sha256-oRP1ZvRmE8eqYmJIuZSad3/BVicmAFkBJ4qSaiD6F0E=";

  meta = {
    description = "PostgreSQL control daemon for Multigres cluster lifecycle management";
    mainProgram = "pgctld";
    license = lib.licenses.asl20;
    platforms = lib.platforms.unix;
  };
}
