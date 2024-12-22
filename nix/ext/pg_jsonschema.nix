{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_12_6, cargo, rust-bin }:
let
  rustVersion = "1.80.0";
  cargo = rust-bin.stable.${rustVersion}.default;
in
buildPgrxExtension_0_12_6 rec {
  pname = "pg_jsonschema";
  version = "0.3.3";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-Au1mqatoFKVq9EzJrpu1FVq5a1kBb510sfC980mDlsU=";
  };

  nativeBuildInputs = [ cargo ];
  buildInputs = [ postgresql ];
  # update the following array when the pg_jsonschema version is updated
  # required to ensure that extensions update scripts from previous versions are generated

  previousVersions = ["0.3.1" "0.3.0" "0.2.0" "0.1.4" "0.1.4" "0.1.2" "0.1.1" "0.1.0"];
  CARGO="${cargo}/bin/cargo";
  #darwin env needs PGPORT to be unique for build to not clash with other pgrx extensions
  env = lib.optionalAttrs stdenv.isDarwin {
    POSTGRES_LIB = "${postgresql}/lib";
    RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
    PGPORT = "5433";
  };

  cargoLock = {
    lockFile = "${src}/Cargo.lock";
    allowBuiltinFetchGit = false;
  };
  
  # FIXME (aseipp): testsuite tries to write files into /nix/store; we'll have
  # to fix this a bit later.
  doCheck = false;

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
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}