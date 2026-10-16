{
  lib,
  stdenv,
  awscli2,
  jq,
  packer,
  yq-go,
  writeShellApplication,
  ...
}:

let
  root = ../../..;
  amiSources = stdenv.mkDerivation {
    name = "amiSources";
    src = lib.fileset.toSource {
      inherit root;
      fileset = lib.fileset.unions [
        (root + "/ansible")
        (root + "/audit-specs")
        (root + "/migrations")
        (root + "/packer")
      ];
    };

    phases = [
      "unpackPhase"
      "installPhase"
    ];
    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';
  };
in
writeShellApplication {
  name = "build-ami";

  runtimeInputs = [
    awscli2
    jq
    packer
    yq-go
  ];

  text = lib.replaceStrings [ "@out@" "@amiSources@" ] [ (placeholder "out") (toString amiSources) ] (
    builtins.readFile ./build-ami.sh
  );

  meta = {
    description = "Build stage-1 and stage-2 AMIs with Packer";
    longDescription = ''
      Stage 1 always builds a new AMI tagged with an input hash computed from the source files that affect the build.
      Stage 2 finds the matching stage-1 AMI by input hash, PostgreSQL version, architecture, source SHA, and execution ID and uses it as its source image.
    '';
  };
}
