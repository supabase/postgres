{
  coreutils,
  nix,
  writeShellApplication,
}:
writeShellApplication {
  name = "dbmate-tool";

  runtimeInputs = [
    coreutils
    nix
  ];

  text = builtins.readFile ./dbmate-tool.sh;

  meta.description = "Regenerate migrations/schema-<version>.sql from the schema-dump package";
}
