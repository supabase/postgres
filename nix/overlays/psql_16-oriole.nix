final: prev: {
  postgresql_16 = prev.postgresql_16.overrideAttrs (old: {
    pname = "postgresql_16";
    version = "16_29";
    src = prev.fetchurl {
      url = "https://github.com/orioledb/postgres/archive/refs/tags/patches16_29.tar.gz";
      sha256 = "sha256-JiC4upjta7OWOfnuxgo/KL41tWcsBUyykOJakn6XjvA=";
    };
    buildInputs = old.buildInputs ++ [
      prev.bison
      prev.docbook5
      prev.docbook_xsl
      prev.docbook_xsl_ns
      prev.docbook_xml_dtd_45
      prev.flex
      prev.libxslt
      prev.perl
    ];
  });
  postgresql_orioledb_16 = final.postgresql_16;
}
