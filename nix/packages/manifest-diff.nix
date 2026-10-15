{
  writeShellApplication,
  diffutils,
  gnused,
  coreutils,
}:
writeShellApplication {
  name = "manifest-diff";
  runtimeInputs = [
    diffutils
    gnused
    coreutils
  ];
  text = ''
    if [ "$#" -lt 4 ]; then
      echo "Usage: manifest-diff <manifest_path> <current_manifest_path> <publish_hint> <diff_path>" >&2
      exit 1
    fi
    MANIFEST_PATH="$1"
    CURRENT_MANIFEST_PATH="$2"
    PUBLISH_HINT="$3"
    DIFF_PATH="$4"

    if [ -s "$MANIFEST_PATH" ]; then
      mv "$MANIFEST_PATH" /tmp/baseline-raw.txt
      BASELINE_VERSION=$(sed -n 's/^# version: //p' /tmp/baseline-raw.txt | head -1)
      tail -n +2 /tmp/baseline-raw.txt > /tmp/baseline.txt
    else
      touch /tmp/baseline.txt
      BASELINE_VERSION=""
    fi
    mv "$CURRENT_MANIFEST_PATH" "$MANIFEST_PATH"
    {
      if [ -z "$BASELINE_VERSION" ]; then
        echo "No baseline cached yet. $PUBLISH_HINT"
      elif diff -q /tmp/baseline.txt "$MANIFEST_PATH" > /dev/null; then
        echo "No changes vs baseline $BASELINE_VERSION."
      else
        echo "baseline: $BASELINE_VERSION"
        diff \
          --old-line-format='-%L' \
          --new-line-format='+%L' \
          --unchanged-group-format=$'... %dn unchanged\n' \
          /tmp/baseline.txt "$MANIFEST_PATH" || true
      fi
    } | tee "$DIFF_PATH"
  '';
}
