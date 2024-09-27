{ lib
, stdenv
, fetchFromGitHub
, postgresql
, buildPgrxExtension_0_12_5
, cargo-pgrx
, rust-bin
}:

let
  rustVersion = "1.80.0";
  rust = rust-bin.stable.${rustVersion}.default;
in

buildPgrxExtension_0_12_5 rec {
  inherit postgresql;

  # Pass the paths to cargo and rustc
  CARGO = "${rust}/bin/cargo";
  RUSTC = "${rust}/bin/rustc";
  pname = "pg_jsonschema";
  version = "0.3.1";

  src = fetchFromGitHub {
    owner = "supabase";
    repo = "pg_jsonschema";
    rev = "fbee35d816858feb394ccc6e1368efab249de687";
    hash = "sha256-Kitc94qWfOmDg6o73F+DXlB9UWt/KYLWiWx8i5Fxxoo=";
  };

  nativeBuildInputs = [ rust ];
  buildInputs = [ postgresql ];

  previousVersions = ["0.3.0" "0.2.0" "0.1.4" "0.1.4" "0.1.2" "0.1.1" "0.1.0"];

  # Environment variables for Darwin
  env = lib.optionals stdenv.isDarwin {
    POSTGRES_LIB = "${postgresql}/lib";
    RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
    PGPORT = "5433";
  };

  # Disable tests if they're trying to write to /nix/store
  doCheck = false;

  cargoHash = "sha256-y+IZZlqeSdlXhEPCl6WT8YrVuz76MbJQDCTjhJ1+Fow=";

  preBuild = ''
    echo "Processing git tags..."
    echo '${builtins.concatStringsSep "," previousVersions}' | sed 's/,/\n/g' > git_tags.txt
  '';

  postInstall = ''
    echo "Creating SQL files for previous versions..."
    current_version="${version}"
    sql_file="$out/share/postgresql/extension/pg_jsonschema--$current_version.sql"
    
    if [ -f "$sql_file" ]; then
      while read -r previous_version; do
        if [ "$(printf '%s\n' "$previous_version" "$current_version" | sort -V | head -n1)" = "$previous_version" ] && [ "$previous_version" != "$current_version" ]; then
          new_file="$out/share/postgresql/extension/pg_jsonschema--$previous_version--$current_version.sql"
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
    description = "JSON Schema Validation for PostgreSQL";
    homepage = "https://github.com/supabase/pg_jsonschema";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
