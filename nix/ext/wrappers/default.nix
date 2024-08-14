{ lib
, stdenv
, fetchFromGitHub
, openssl
, pkg-config
, postgresql
, buildPgrxExtension_0_11_3
, cargo
, darwin
, jq
}:

let
  gitTags = builtins.fromJSON (builtins.readFile (builtins.fetchurl {
    url = "https://api.github.com/repos/supabase/wrappers/tags";
    sha256 = "0pvavn0f8wnaszq4bmvjkadm6xbvf91rbhcmmgjasqajb69vskv9"; # Replace with actual hash
  }));
in
buildPgrxExtension_0_11_3 rec {
  pname = "supabase-wrappers";
  version = "0.4.1";
  inherit postgresql;
  src = fetchFromGitHub {
    owner = "supabase";
    repo = "wrappers";
    rev = "v${version}";
    hash = "sha256-AU9Y43qEMcIBVBThu+Aor1HCtfFIg+CdkzK9IxVdkzM=";
  };
  nativeBuildInputs = [ pkg-config cargo jq ];
  buildInputs = [ openssl ] ++ lib.optionals (stdenv.isDarwin) [ 
    darwin.apple_sdk.frameworks.CoreFoundation 
    darwin.apple_sdk.frameworks.Security 
    darwin.apple_sdk.frameworks.SystemConfiguration 
  ];
  OPENSSL_NO_VENDOR = 1;
  
  CARGO="${cargo}/bin/cargo";
  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    outputHashes = {
      "clickhouse-rs-1.0.0-alpha.1" = "sha256-0zmoUo/GLyCKDLkpBsnLAyGs1xz6cubJhn+eVqMEMaw=";
    };
  };
  postPatch = "cp ${cargoLock.lockFile} Cargo.lock";
  buildAndTestSubdir = "wrappers";
  buildFeatures = [
    "helloworld_fdw"
    "bigquery_fdw"
    "clickhouse_fdw"
    "stripe_fdw"
    "firebase_fdw"
    "s3_fdw"
    "airtable_fdw"
    "logflare_fdw"
    "auth0_fdw"
    "mssql_fdw"
    "redis_fdw"
    "cognito_fdw"
    "wasm_fdw"
  ];
  doCheck = false;

  preBuild = ''
    echo "Processing git tags..."
    echo '${builtins.toJSON gitTags}' | ${jq}/bin/jq -r '.[].name' | sort -rV > git_tags.txt
  '';

  postInstall = ''
    echo "Creating SQL files for previous versions..."
    current_version="${version}"
    sql_file="$out/share/postgresql/extension/wrappers--$current_version.sql"
    
    if [ -f "$sql_file" ]; then
      while read -r tag; do
        tag_version=$(echo "$tag" | sed 's/^v//')
        if [ "$(printf '%s\n' "$tag_version" "$current_version" | sort -V | head -n1)" = "$tag_version" ] && [ "$tag_version" != "$current_version" ]; then
          new_file="$out/share/postgresql/extension/wrappers--$tag_version--$current_version.sql"
          echo "Creating $new_file"
          cp "$sql_file" "$new_file"
        fi
      done < git_tags.txt
    else
      echo "Warning: $sql_file not found"
    fi
    rm git_tags.txt
  '';

  meta = with lib; {
    description = "Various Foreign Data Wrappers (FDWs) for PostreSQL";
    homepage = "https://github.com/supabase/wrappers";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
