{ lib
, stdenv
, fetchFromGitHub
, openssl
, pkg-config
, postgresql
, buildPgrxExtension_0_12_6
, cargo
, darwin
, jq
, rust-bin
, git
}:
let
  rustVersion = "1.80.0";
  cargo = rust-bin.stable.${rustVersion}.default;
in
buildPgrxExtension_0_12_6 rec {
  pname = "supabase-wrappers";
  version = "0.4.3";
  # update the following array when the wrappers version is updated
  # required to ensure that extensions update scripts from previous versions are generated
  previousVersions = ["0.4.2" "0.4.1" "0.4.0" "0.3.1" "0.3.0" "0.2.0" "0.1.19" "0.1.18" "0.1.17" "0.1.16" "0.1.15" "0.1.14" "0.1.12" "0.1.11" "0.1.10" "0.1.9" "0.1.8" "0.1.7" "0.1.6" "0.1.5" "0.1.4" "0.1.1" "0.1.0"];
  inherit postgresql;
  src = fetchFromGitHub {
    owner = "supabase";
    repo = "wrappers";
    rev = "v${version}";
    hash = "sha256-CkoNMoh40zbQL4V49ZNYgv3JjoNWjODtTpHn+L8DdZA=";
  };
 
  nativeBuildInputs = [ pkg-config cargo ];
  buildInputs = [ openssl postgresql git ] ++ lib.optionals (stdenv.isDarwin) [ 
    darwin.apple_sdk.frameworks.CoreFoundation 
    darwin.apple_sdk.frameworks.Security 
    darwin.apple_sdk.frameworks.SystemConfiguration 
  ];

  NIX_LDFLAGS = "-L${postgresql}/lib -lpq";

  # Set necessary environment variables for pgrx
  env = lib.optionalAttrs stdenv.isDarwin {
    POSTGRES_LIB = "${postgresql}/lib";
    RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
    PGPORT = "5435";
  };

  OPENSSL_NO_VENDOR = 1;
  #need to set this to 2 to avoid cpu starvation
  CARGO_BUILD_JOBS = "2";
  CARGO="${cargo}/bin/cargo";
  
  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    allowBuiltinFetchGit = true;
  };
  
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
    echo '${builtins.concatStringsSep "," previousVersions}' | sed 's/,/\n/g' > git_tags.txt
  '';

  postInstall = ''
    echo "Creating SQL files for previous versions..."
    current_version="${version}"
    sql_file="$out/share/postgresql/extension/wrappers--$current_version.sql"
    
    if [ -f "$sql_file" ]; then
      while read -r previous_version; do
        if [ "$(printf '%s\n' "$previous_version" "$current_version" | sort -V | head -n1)" = "$previous_version" ] && [ "$previous_version" != "$current_version" ]; then
          new_file="$out/share/postgresql/extension/wrappers--$previous_version--$current_version.sql"
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
