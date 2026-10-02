{
  lib,
  stdenv,
  awscli2,
  jq,
  packer,
  writeShellApplication,
  ...
}:

let
  root = ../../..;
  packerSources = stdenv.mkDerivation {
    name = "packer-sources";
    src = lib.fileset.toSource {
      inherit root;
      fileset = lib.fileset.unions [
        (root + "/packer")
        (root + "/ansible")
        (root + "/migrations")
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
  ];

  text =
    lib.replaceStrings [ "@out@" "@packerSources@" ] [ (placeholder "out") (toString packerSources) ]
      (builtins.readFile ./build-ami.sh);

  meta = {
    description = "Build stage-1 and stage-2 AMIs with Packer";
    longDescription = ''
      Stage 1 always builds a new AMI tagged with an input hash computed from
      the source files that affect the build. Stage 2 finds the matching
      stage-1 AMI by input hash, PostgreSQL version, architecture, and source SHA
      and uses it as its source image.
    '';
  };
}
