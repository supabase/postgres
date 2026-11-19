{
  gitMinimal,
  gnused,
  writeShellApplication,
}:
writeShellApplication {
  name = "rehash";

  runtimeInputs = [
    gitMinimal
    gnused
  ];

  text = builtins.readFile ./rehash.sh;
}
