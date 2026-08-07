{
  runCommand,
  makeWrapper,
  python3,
  git,
}:
runCommand "ext-explorer"
  {
    nativeBuildInputs = [ makeWrapper ];
  }
  ''
    mkdir -p $out/bin $out/libexec/ext-explorer
    cp ${./ext-explorer/generate.py} $out/libexec/ext-explorer/generate.py
    cp ${./ext-explorer/template.html} $out/libexec/ext-explorer/template.html
    makeWrapper ${python3}/bin/python3 $out/bin/ext-explorer \
      --add-flags "$out/libexec/ext-explorer/generate.py" \
      --prefix PATH : ${git}/bin
  ''
