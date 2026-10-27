{
  lib,
  runCommand,
  build-ami,
  nix-store-paths,
  postgresMajorVersion,
  # File containing the ID of the AMI that passed testinfra, only available to `nix build --no-pure-eval`.
  # Pure evaluation (gen-matrix, nix flake check, ...) leaves it unset, which still yields the same out path.
  amiIdFile ?
    let
      file = builtins.getEnv "AMI_ID_FILE";
    in
    if file == "" then null else /. + file,
}:

let
  root = ../..;
  testSources = lib.fileset.toSource {
    inherit root;
    fileset = lib.fileset.unions [
      (root + "/.github/workflows/testinfra-ami-build.yml")
      (root + "/testinfra")
    ];
  };

  # Context is discarded so building the stamp doesn't pull in the postgres closure;
  # the out path still changes whenever any of these paths change.
  text = builtins.unsafeDiscardStringContext ''
    build-ami=${build-ami}
    nix-store-paths=${nix-store-paths}
    tests=${testSources}
  '';
in
# Temporary: only needed while AMIs are built and tested by packer on AWS, outside of Nix.
# Once Nix builds the AMI itself, that derivation becomes the cache key and this stamp, along with
# gen-matrix's cache check, can be removed.
#
# Receipt that an AMI built from these inputs passed testinfra.
# testinfra-ami-build.yml builds it (and so pushes it to the binary cache) only after the tests pass,
# and skips any AMI whose stamp is already in the cache.
#
# Fixed-output so the out path depends only on `text`: gen-matrix can compute it before any AMI exists,
# while building it still requires the ID of an AMI that was actually tested.
# That makes an unexpected build (e.g. the stamp ending up in checks or legacyPackages and so in the
# nix-build.yml package matrix) fail loudly instead of pushing a stamp that skips every AMI build.
runCommand "ami-test-stamp-${postgresMajorVersion}"
  {
    inherit text;
    passAsFile = [ "text" ];
    amiIdFile = if amiIdFile == null then "" else amiIdFile;
    outputHashMode = "flat";
    outputHashAlgo = "sha256";
    outputHash = builtins.hashString "sha256" text;
  }
  ''
    if [[ -z $amiIdFile ]]; then
      echo "error: no AMI ID given, set AMI_ID_FILE and build with --no-pure-eval after testinfra passes" >&2
      exit 1
    fi
    amiId=$(<"$amiIdFile")
    if [[ ! $amiId =~ ^ami-[0-9a-f]{8,17}$ ]]; then
      echo "error: '$amiId' from $amiIdFile is not an AMI ID" >&2
      exit 1
    fi
    echo "AMI $amiId passed testinfra"
    cp "$textPath" "$out"
  ''
