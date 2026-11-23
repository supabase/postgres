{
  coreutils,
  openssl,
  writeShellApplication,
}:
# TODO(mmlb): consolidate the pgsodium getkey scripts onto this one.
# Something like this is used in a bunch of places so lets consolidate them.
# Will need to handle stable keys instead of always creating.
# Also need to be POSIX only so that cli bundle's use will continue to work.
writeShellApplication {
  name = "pgsodium-getkey";

  runtimeInputs = [
    coreutils
    openssl
  ];

  text = builtins.readFile ./getkey-script.sh;

  meta.description = "pgsodium getkey script that generates a throwaway key for tests";
}
