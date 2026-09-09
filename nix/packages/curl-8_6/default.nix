{
  curl,
  fetchurl,
}:

let
  version = "8.6.0";
in
curl.overrideAttrs (old: {
  inherit version;

  src = fetchurl {
    urls = [
      "https://curl.se/download/curl-${version}.tar.xz"
      "https://github.com/curl/curl/releases/download/curl-${
        builtins.replaceStrings [ "." ] [ "_" ] version
      }/curl-${version}.tar.xz"
    ];
    hash = "sha256-PM1V2Rr5UWU534BiX4GMc03G8uz5utozx2dl6ZEh2xU=";
  };

  configureFlags = builtins.filter (
    flag:
    !builtins.elem flag [
      # these flags don't exist in curl 8.6 so would fail the configure when supplied
      "--with-nghttp3"
      "--with-ngtcp2"
    ]
  ) old.configureFlags;

  meta = old.meta // {
    knownVulnerabilities = [
      "curl 8.6.0 is outdated and has multiple publicly known vulnerabilities"
    ];
  };
})
