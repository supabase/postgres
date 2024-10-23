# { self, fetchurl, ... }:

# let
#   generic = import ./generic.nix rec {
#     version = "16";
#     hash = "sha256-29uHUACwZKh8e4zJ9tWzEhLNjEuh6P31KbpxnMEhtuI=";
#     src = fetchurl {
#       url = "https://github.com/orioledb/postgres/archive/refs/tags/patches16_31.tar.gz";
#       sha256 = hash;
#     };
#   };
# in
# generic.overrideAttrs (oldAttrs: {
#   inherit generic;
# })
# orioledb-16.nix
import ./generic.nix {
  version = "16_31";
  hash = "sha256-29uHUACwZKh8e4zJ9tWzEhLNjEuh6P31KbpxnMEhtuI=";
}
