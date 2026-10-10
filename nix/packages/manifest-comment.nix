{
  writeShellApplication,
  coreutils,
}:
writeShellApplication {
  name = "manifest-comment";
  runtimeInputs = [
    coreutils
  ];
  text = ''
    if [ "$#" -lt 4 ]; then
      echo "Usage: manifest-comment <marker> <title> <diffs_prefix> <run_url>" >&2
      exit 1
    fi
    shopt -s nullglob
    MARKER="$1"
    TITLE="$2"
    PREFIX="$3"
    RUN_URL="$4"

    fence=$'\x60\x60\x60'
    dirs=("diffs/''${PREFIX}"-*)
    if [ "''${#dirs[@]}" -eq 0 ]; then
      exit 0
    fi

    echo "<!-- $MARKER -->"
    echo "## $TITLE"
    echo

    for dir in "''${dirs[@]}"; do
      leg="''${dir#diffs/"''${PREFIX}"-}"
      file="$dir/manifest-diff.txt"
      first="$(head -1 "$file")"
      if [[ "$first" != "baseline: "* ]]; then
        printf '<details>\n<summary>%s: %s</summary>\n</details>\n\n' "$leg" "$first"
        continue
      fi
      body="$(tail -n +2 "$file")"
      printf '<details>\n<summary>%s: changed (%s)</summary>\n\n%sdiff\n%s\n%s\n' "$leg" "$first" "$fence" "''${body:0:6000}" "$fence"
      if [ "''${#body}" -gt 6000 ]; then
        echo "truncated, [full output]($RUN_URL)"
      fi
      printf '</details>\n\n'
    done
  '';
}
