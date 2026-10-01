{
  jq,
  lib,
  runtimeShell,
  stdenvNoCC,
}:

stdenvNoCC.mkDerivation {
  pname = "github-matrix";
  version = "0.2.0";

  src = ./.;

  nativeCheckInputs = [ jq ];

  dontBuild = true;
  doCheck = true;

  checkPhase = ''
    runHook preCheck
    bash tests/run.sh
    runHook postCheck
  '';

  installPhase = ''
    runHook preInstall

    install -Dm644 github-matrix.jq -t $out/share/github-matrix
    mkdir -p $out/bin
    cat >$out/bin/github-matrix <<'EOF'
    #!${runtimeShell}
    # usage: github-matrix <system> < jobs.jsonl
    set -euo pipefail
    exec ${lib.getExe jq} -r -s --arg system "''${1:?system}" -f ${placeholder "out"}/share/github-matrix/github-matrix.jq
    EOF
    chmod 755 $out/bin/github-matrix

    runHook postInstall
  '';

  meta = {
    description = "Turn nix-eval-jobs-shaped JSONL into GitHub Actions build matrices";
    mainProgram = "github-matrix";
  };
}
