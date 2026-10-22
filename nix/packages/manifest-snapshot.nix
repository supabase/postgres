{
  writeShellApplication,
  libarchive,
  coreutils,
}:
writeShellApplication {
  name = "manifest-snapshot";
  runtimeInputs = [
    libarchive
    coreutils
  ];
  text = builtins.readFile ../../testinfra/manifest-snapshot.sh;
}
