{
  writeShellApplication,
  gnused,
  gnugrep,
  coreutils,
}:
writeShellApplication {
  name = "manifest-comment";
  runtimeInputs = [
    gnused
    gnugrep
    coreutils
  ];
  text = ''
    if [ "$#" -lt 5 ]; then
      echo "Usage: manifest-comment <marker> <title> <description> <diffs_prefix> <run_url>" >&2
      exit 1
    fi
    shopt -s nullglob
    MARKER="$1"
    TITLE="$2"
    DESCRIPTION="$3"
    PREFIX="$4"
    RUN_URL="$5"

    dirs=("diffs/''${PREFIX}"-*)
    if [ "''${#dirs[@]}" -eq 0 ]; then
      exit 0
    fi

    echo "<!-- $MARKER -->"
    echo "## $TITLE"
    echo "$DESCRIPTION"
    echo

    for dir in "''${dirs[@]}"; do
      leg="''${dir#diffs/"''${PREFIX}"-}"
      file="$dir/manifest-diff.txt"
      if [ ! -f "$file" ]; then
        echo "<details>"
        echo "<summary>''${leg}: diff unavailable (job failed or skipped)</summary>"
        echo "</details>"
        echo
        continue
      fi
      if grep -q "^No baseline cached yet" "$file"; then
        echo "<details>"
        echo "<summary>''${leg}: no baseline cached yet</summary>"
        echo
        cat "$file"
        echo "</details>"
        echo
        continue
      fi
      if grep -q "^No changes vs baseline" "$file"; then
        echo "<details>"
        echo "<summary>''${leg}: $(cat "$file")</summary>"
        echo "</details>"
        echo
        continue
      fi
      baseline="$(sed -n 's/^baseline: //p' "$file" | head -1)"
      tail -n +2 "$file" > "$file.body"
      file="$file.body"
      echo "<details>"
      echo "<summary>''${leg}: changed (baseline: ''${baseline})</summary>"
      echo
      echo '```diff'
      head -c 6000 "$file"
      echo '```'
      if [ "$(wc -c < "$file")" -gt 6000 ]; then
        echo "truncated, [full output]($RUN_URL)"
      fi
      echo "</details>"
      echo
    done
  '';
}
