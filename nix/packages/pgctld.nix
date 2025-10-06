{
  pkgs,
  inputs,
  lib,
  fetchFromGitHub,
  ...
}:
let
  go125 = inputs.nixpkgs-go125.legacyPackages.${pkgs.system}.go_1_25;
  buildGoModule = pkgs.buildGoModule.override { go = go125; };
in
buildGoModule rec {
  pname = "pgctld";
  version = "0.1.0";

  src = fetchFromGitHub {
    owner = "multigres";
    repo = "multigres";
    rev = "main";
    sha256 = "sha256-XvsJJptrjMh4eRNjSHNnNbZFl+QDLiivV3C4YHv8Bjw=";
  };

  vendorHash = "sha256-5NgDpMDFaMs7imtUy1V7Y6hmRN+gkq1+tWgok/ccQY8=";

  # Only build the pgctld command
  subPackages = [ "go/cmd/pgctld" ];

  ldflags = [
    "-s"
    "-w"
  ];

  meta = with lib; {
    homepage = "https://github.com/multigres/multigres";
    description = "PostgreSQL control daemon for Multigres cluster management";
    license = licenses.asl20;
    mainProgram = "pgctld";
  };
}
