final: prev: {
  postgis = prev.postgresqlPackages.postgis.overrideAttrs (old: {
    version = "3.3.2";
    sha256 = "";
  });
  postgresqlPackages.postgis = final.postgis;
}
