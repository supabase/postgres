{ pkgs }:
rec {
  # The only libc locales AMIs and Docker images ship.
  shippedLocales = [
    "en_US.UTF-8/UTF-8"
    "C.UTF-8/UTF-8"
  ];

  corpus = pkgs.runCommand "collation-corpus" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    PYTHONIOENCODING=utf-8 python3 ${./corpus.py} > $out
  '';

  fingerprints =
    glibcPkgs:
    let
      localeData = glibcPkgs.glibcLocales.override {
        allLocales = false;
        locales = shippedLocales;
      };
    in
    pkgs.runCommand "collation-fingerprints-${glibcPkgs.glibc.version}" { } ''
      export LOCALE_ARCHIVE=${localeData}/lib/locale/locale-archive
      for entry in ${toString shippedLocales}; do
        name=''${entry%%/*}
        # sort silently falls back to C when the locale is missing.
        [ "$(LC_ALL=$name ${glibcPkgs.glibc.bin}/bin/locale charmap)" = UTF-8 ]
        printf '%s\t%s\n' "$name" "$(LC_ALL=$name ${glibcPkgs.coreutils}/bin/sort ${corpus} | sha256sum | cut -d' ' -f1)"
      done > $out
    '';

  compare =
    old: new:
    pkgs.runCommand "collation-compare-${old.glibc.version}-${new.glibc.version}" { } ''
      diff ${fingerprints old} ${fingerprints new}
      touch $out
    '';

  icuPin =
    { reference, postgresqls }:
    let
      describe =
        icu:
        "${icu.version} ${icu.src.outputHash} patches=[${toString (map toString (icu.patches or [ ]))}]";
      expected = describe reference.icu75;
      icuOf = pg: pkgs.lib.findFirst (input: (input.pname or "") == "icu4c") null pg.buildInputs;
      actual = pg: if icuOf pg == null then "no ICU" else describe (icuOf pg);
      mismatched = builtins.filter (pg: actual pg != expected) postgresqls;
    in
    if mismatched == [ ] then
      pkgs.writeText "icu-pin" expected
    else
      throw "Postgres ICU differs from the pinned ${expected}: ${
        toString (map (pg: "${pg.name} links ${actual pg}") mismatched)
      }";
}
