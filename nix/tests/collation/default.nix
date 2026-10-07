{ pkgs }:
rec {
  # The only libc locales AMIs and Docker images ship. Everything else is ICU.
  shippedLocales = [
    "en_US.UTF-8/UTF-8"
    "C.UTF-8/UTF-8"
  ];

  # Fails evaluation unless every Postgres links the same ICU as `reference`:
  # same version, same source, no patches.
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

  corpus = pkgs.runCommand "collation-corpus" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    PYTHONIOENCODING=utf-8 python3 ${./corpus.py} > $out
  '';

  # Sort fingerprint per locale, using the glibc, locale data, and sort from
  # `glibcPkgs`. `locales` are glibcLocales entries like "en_US.UTF-8/UTF-8",
  # or null for every locale glibc ships.
  fingerprints =
    {
      glibcPkgs,
      locales ? null,
    }:
    let
      localeData =
        if locales == null then
          glibcPkgs.glibcLocales
        else
          glibcPkgs.glibcLocales.override {
            allLocales = false;
            inherit locales;
          };
    in
    pkgs.runCommand "collation-fingerprints-${glibcPkgs.glibc.version}" { } ''
      export LOCALE_ARCHIVE=${localeData}/lib/locale/locale-archive
      ${glibcPkgs.glibc.bin}/bin/locale -a | grep -iE 'utf-?8$' | sort > names
      while read -r name; do
        hash=$(LC_ALL=$name ${glibcPkgs.coreutils}/bin/sort ${corpus} | sha256sum | cut -d' ' -f1)
        printf '%s\t%s\n' "$name" "$hash"
      done < names > $out
    '';

  # Fails when any locale sorts the corpus differently under `new` than under
  # `old`, or when the two ship different locales.
  compare =
    {
      old,
      new,
      locales ? null,
    }:
    let
      a = fingerprints {
        glibcPkgs = old;
        inherit locales;
      };
      b = fingerprints {
        glibcPkgs = new;
        inherit locales;
      };
    in
    pkgs.runCommand "collation-compare-${old.glibc.version}-${new.glibc.version}" { } ''
      if ! diff ${a} ${b} > diff.txt; then
        echo "glibc ${old.glibc.name} and ${new.glibc.name} sort differently in:" >&2
        cut -f1 diff.txt | grep -E '^[<>]' | sed -E 's/^[<>] //' | sort -u >&2
        exit 1
      fi
      echo "glibc ${old.glibc.name} and ${new.glibc.name} sort identically in $(wc -l < ${a}) locales" > $out
    '';
}
