{
  writeShellApplication,
  coreutils,
  diffutils,
  gnugrep,
  manifest-snapshot,
  site-profile-sanity,
}:
writeShellApplication {
  name = "site-profile-roundtrip";
  runtimeInputs = [
    coreutils
    diffutils
    gnugrep
    manifest-snapshot
    site-profile-sanity
  ];
  text = builtins.readFile ../../testinfra/site-profile-roundtrip.sh;
}
