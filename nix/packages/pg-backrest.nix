{
  fetchurl,
  pgbackrest,
}:
pgbackrest.overrideAttrs (
  finalAttrs: prevAttrs: {
    version = "2.59.1";

    # Deliberately the release tarball rather than fetchFromGitHub. As of 2.59.0
    # upstream's .gitattributes marks /src/build as export-ignore, so the GitHub
    # tag archive omits the code-generation tooling *and* the generated sources
    # *and* the "dist" marker file — it simply cannot be built (meson fails with
    # "File build/common/regExp.c does not exist").
    src = fetchurl {
      url = "https://github.com/pgbackrest/pgbackrest/releases/download/release/${finalAttrs.version}/pgbackrest-${finalAttrs.version}.tar.gz";
      hash = "sha256-HNUir8M7j/hG74jFXcI4cXyciBek9sp8n2SIfenHQC0=";
    };

    # 2.59.0 adds an optional libsystemd dependency for systemd notify support.
    # Nonexistent on darwin.
    mesonFlags = (prevAttrs.mesonFlags or [ ]) ++ [ "-Dlibsystemd=disabled" ];
  }
)
