{ lib, runCommand }:

# !!! Temporary !!!
# Packer builds and tests the AMIs and qemu images outside of Nix, so we need this stamp to avoid unnecessary rebuilds/tests.
# When Nix builds them itself, its derivation can be the cache key.
# Then remove the stamps and the CI cache checks that skip builds.
#
# A stamp is a receipt that an artifact built from `inputs` passed its tests.
# CI builds the stamp only after the tests pass, which pushes it to the binary cache.
# CI skips any artifact whose stamp is already in the cache.
#
# The stamp is a fixed-output derivation, so its store path depends only on `inputs`.
# This lets CI compute the path before the artifact exists.
# Building the stamp still needs the ID of an artifact that was actually tested.
# So an unplanned build fails with an error.
# An example is the stamp landing in checks or legacyPackages, and so in the nix-build.yml package matrix.
# Without the failure, we would push a stamp that makes CI skip every build.
{
  name, # Name of the stamp in the Nix store.
  inputs, # Attrset of name -> path. The stamp's store path changes when any of these paths change.
  artifact, # What STAMP_FILE must contain, for error messages, e.g. "AMI ID".
  pattern, # Regex STAMP_FILE's contents must match.
}:

let
  # File containing the ID of the artifact that passed its tests, only available to `nix build --no-pure-eval`.
  # Pure evaluation (gen-matrix, nix flake check, ...) leaves it empty, which still yields the same out path.
  # Only a non-empty path may be coerced: `/. + ""` is `/`, which would copy the whole filesystem into the store.
  stampFile =
    let
      file = builtins.getEnv "STAMP_FILE";
    in
    if file == "" then "" else /. + file;

  # Context is discarded so building the stamp doesn't pull in the postgres closure.
  # The out path still changes whenever any of these paths change.
  text = builtins.unsafeDiscardStringContext (
    lib.concatLines (lib.mapAttrsToList (n: path: "${n}=${path}") inputs)
  );
in
runCommand name
  {
    inherit
      text
      artifact
      pattern
      stampFile
      ;
    passAsFile = [ "text" ];
    outputHashMode = "flat";
    outputHashAlgo = "sha256";
    outputHash = builtins.hashString "sha256" text;
  }
  ''
    if [[ -z $stampFile ]]; then
      echo "error: no $artifact given, this is a guard against local builds. Push so CI runs and does the right thing." >&2 # intentionally vague
      exit 1
    fi
    value=$(<"$stampFile")
    if [[ ! $value =~ $pattern ]]; then
      echo "error: '$value' from $stampFile is not a valid $artifact" >&2
      exit 1
    fi
    echo "$artifact $value passed its tests"
    cp "$textPath" "$out"
  ''
