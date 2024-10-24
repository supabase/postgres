final: prev: {
  pg_orioledb = prev.postgresql_16.overrideAttrs (old: {
    pname = "postgresql_orioledb";
    version = "16_31";
    src = prev.fetchurl {
      url = "https://github.com/orioledb/postgres/archive/refs/tags/patches16_31.tar.gz";
      sha256 = "sha256-29uHUACwZKh8e4zJ9tWzEhLNjEuh6P31KbpxnMEhtuI=";
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
  postgresql_orioledb = final.pg_orioledb;
}
