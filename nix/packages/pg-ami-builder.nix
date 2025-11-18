{
  pkgs,
  lib,
  buildGoModule,
  makeWrapper,
  packer,
}:

buildGoModule {
  pname = "pg-ami-builder";
  version = "0.1.0";

  src = ./pg-ami-builder;

  vendorHash = "sha256-6zdLFpc9TvX5OqoFuL4d39MfO6Bk0GGuXdJwrsRkYwc=";

  nativeBuildInputs = with pkgs; [
    makeWrapper
    awscli2
    git
  ];

  # Disable CGO for static binary
  env.CGO_ENABLED = 0;

  # Build flags for reduced binary size and version info
  ldflags = [
    "-s"
    "-w"
    "-X main.Version=0.1.0"
  ];

  # Run tests during build
  checkPhase = ''
    runHook preCheck
    go test ./... -short
    runHook postCheck
  '';

  # Wrap binary with runtime dependencies
  postInstall = ''
    wrapProgram $out/bin/pg-ami-builder \
      --prefix PATH : ${lib.makeBinPath [ packer ]}
  '';

  meta = with lib; {
    description = "Local AMI development tool for Supabase Postgres";
    homepage = "https://github.com/supabase/postgres";
    license = licenses.asl20;
    maintainers = [ ];
    mainProgram = "pg-ami-builder";
  };
}
