{
  gitMinimal,
  gnused,
  nix-update,
  writeShellApplication,
}:
writeShellApplication {
  name = "rehash";

  runtimeInputs = [
    gitMinimal
    gnused
    nix-update
  ];

  text = builtins.readFile ./rehash.sh;
}
