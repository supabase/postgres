{ pkgs }:
let
  inherit (pkgs) lib;
  ubuntuSnapshot = "https://snapshot.ubuntu.com/ubuntu/20261001T000000Z/pool/main/g/glibc";
  ubuntuReleases = {
    "24.04" = {
      version = "2.39-0ubuntu8.9";
      checked = [
        "en_US.UTF-8/UTF-8"
        "C.UTF-8/UTF-8"
      ];
      localesDeb = "sha256-+DEO9LpEKEXPXUSlzj1desy2WbrpazoJmQAhMiCc02c=";
      x86_64-linux = {
        arch = "amd64";
        libc6 = "sha256-/1VX2ZtR92HEt8kjaLnMRVZe2hffm/nrSxNNCYJQCL4=";
        libc-bin = "sha256-BmOYoG7xohjUEJRh1MY26v6DMirRmxed6e969Cs/7Fg=";
      };
      aarch64-linux = {
        arch = "arm64";
        libc6 = "sha256-rRCXl8X3il7rbUwpa/uq5osjkRGgyawOuXuNQwKErEU=";
        libc-bin = "sha256-Wpb+YseAOkuIaymvu2e15BlS3pGKvSF9K4/fvETDty0=";
      };
    };
    "20.04" = {
      version = "2.31-0ubuntu9.18";
      # Before 2.35 Debian's C.UTF-8 is not in code point order.
      checked = [ "en_US.UTF-8/UTF-8" ];
      localesDeb = "sha256-Gz2hU7tttEU+vzVfUrKduEtHO9YxXy/LRery346Zwqw=";
      x86_64-linux = {
        arch = "amd64";
        libc6 = "sha256-GyKBqsSTXf6h+J38GeRF/btFMDICr2BnnMuL8DXwgaA=";
        libc-bin = "sha256-RKPDJnUlLFWZjgg/URVk/ltlQK0YnWtGNVrSNyue1Jg=";
      };
      aarch64-linux = {
        arch = "arm64";
        libc6 = "sha256-T/YNhK1486pZgpfcaWZUn6ZIn1dZnxl1Yq2RVH84jaA=";
        libc-bin = "sha256-V3v34GM3xI89Uv85CD4GMhFFp/9kGKrVhBZLkF9z7Dg=";
      };
    };
  };
in
rec {
  # The only libc locales AMIs and Docker images ship.
  shippedLocales = [
    "en_US.UTF-8/UTF-8"
    "C.UTF-8/UTF-8"
  ];

  corpus = pkgs.runCommand "collation-corpus" { nativeBuildInputs = [ pkgs.python3 ]; } ''
    PYTHONIOENCODING=utf-8 python3 ${./corpus.py} > $out
  '';

  # AMIs build /usr/lib/locale/locale-archive with Ubuntu's locale-gen and
  # the nix-built postgres reads it through LOCALE_ARCHIVE.
  ubuntuLocaleArchive =
    release:
    let
      inherit (ubuntuReleases.${release}) version;
      debs = ubuntuReleases.${release}.${pkgs.stdenv.hostPlatform.system};
      fetchDeb =
        name: arch: hash:
        pkgs.fetchurl {
          url = "${ubuntuSnapshot}/${name}_${version}_${arch}.deb";
          inherit hash;
        };
      libc6 = fetchDeb "libc6" debs.arch debs.libc6;
      libcBin = fetchDeb "libc-bin" debs.arch debs.libc-bin;
      locales = fetchDeb "locales" "all" ubuntuReleases.${release}.localesDeb;
    in
    pkgs.runCommand "ubuntu-${release}-locale-archive-${version}"
      {
        nativeBuildInputs = [
          pkgs.dpkg
          pkgs.gzip
        ];
      }
      ''
        root=$PWD/root
        for deb in ${libc6} ${libcBin} ${locales}; do
          dpkg-deb -x $deb $root
        done
        ld=$(find $root -type f \( -name 'ld-linux-*' -o -name 'ld-[0-9]*.so' \) | head -n1)
        mkdir -p $out/usr/lib/locale
        export I18NPATH=$root/usr/share/i18n
        for entry in ${toString ubuntuReleases.${release}.checked}; do
          name=''${entry%%/*}
          $ld --library-path $(dirname $ld) \
            $root/usr/bin/localedef --prefix=$out -c -i ''${name%%.*} -f UTF-8 $name
        done
        test -s $out/usr/lib/locale/locale-archive
      '';

  fingerprints =
    {
      name,
      glibcPkgs,
      localeArchive,
      locales,
    }:
    pkgs.runCommand "collation-fingerprints-${name}" { } ''
      export LOCALE_ARCHIVE=${localeArchive}
      for entry in ${toString locales}; do
        name=''${entry%%/*}
        # sort silently falls back to C when the locale is missing.
        [ "$(LC_ALL=$name ${glibcPkgs.glibc.bin}/bin/locale charmap)" = UTF-8 ]
        printf '%s\t%s\n' "$name" "$(LC_ALL=$name ${glibcPkgs.coreutils}/bin/sort ${corpus} | sha256sum | cut -d' ' -f1)"
      done > $out
    '';

  nixpkgsFingerprints =
    glibcPkgs: locales:
    fingerprints {
      name = "nixpkgs-${glibcPkgs.glibc.version}";
      inherit glibcPkgs locales;
      localeArchive = "${
        glibcPkgs.glibcLocales.override {
          allLocales = false;
          inherit locales;
        }
      }/lib/locale/locale-archive";
    };

  ubuntuFingerprints =
    release: glibcPkgs:
    fingerprints {
      name = "ubuntu-${release}-${ubuntuReleases.${release}.version}";
      inherit glibcPkgs;
      locales = ubuntuReleases.${release}.checked;
      localeArchive = "${ubuntuLocaleArchive release}/usr/lib/locale/locale-archive";
    };

  compare =
    old: new:
    pkgs.runCommand "collation-compare-${old.glibc.version}-${new.glibc.version}" { } ''
      diff ${nixpkgsFingerprints old shippedLocales} ${nixpkgsFingerprints new shippedLocales}
      touch $out
    '';

  compareUbuntu =
    release: reference: runtime:
    pkgs.runCommand "collation-compare-ubuntu-${release}-${reference.glibc.version}" { } ''
      diff ${
        nixpkgsFingerprints reference ubuntuReleases.${release}.checked
      } ${ubuntuFingerprints release runtime}
      touch $out
    '';

  icuPin =
    { reference, postgresqls }:
    let
      describe =
        icu:
        "${icu.version} ${icu.src.outputHash} patches=[${toString (map toString (icu.patches or [ ]))}]";
      expected = describe reference.icu75;
      icuOf = pg: lib.findFirst (input: (input.pname or "") == "icu4c") null pg.buildInputs;
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
