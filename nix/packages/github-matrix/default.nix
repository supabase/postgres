{
  lib,
  nix-eval-jobs,
  python3Packages,
}:
let
  pname = "github-matrix";
in

python3Packages.buildPythonApplication {
  inherit pname;
  version = "0.1.0";
  pyproject = false;

  src = ./.;

  makeWrapperArgs = [ "--suffix PATH : ${lib.makeBinPath [ nix-eval-jobs ]}" ];

  nativeCheckInputs = with python3Packages; [
    pytestCheckHook
    pytest-mypy
  ];

  installPhase = ''
    install -Dm755 github_matrix.py "$out/bin/${pname}"
  '';
}
