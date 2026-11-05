{
  writeShellApplication,
  coreutils,
}:
writeShellApplication {
  name = "site-profile-sanity";
  runtimeInputs = [ coreutils ];
  text = builtins.readFile ../../testinfra/site-profile-sanity.sh;
}
