{ lib, stdenv, fetchFromGitHub, postgresql, buildPgrxExtension_0_11_3, cargo }:

buildPgrxExtension_0_11_3 rec {
  pname = "pg_graphql";
  version = "1.5.7";
  inherit postgresql;

  src = fetchFromGitHub {
    owner = "supabase";
    repo = pname;
    rev = "v${version}";
    hash = "sha256-Q6XfcTKVOjo5pGy8QACc4QCHolKxEGU8e0TTC6Zg8go=";
  };

  # update the following array when the pg_graphql version is updated
  # required to ensure that extensions update scripts from previous versions are generated
  previousVersions = [
    "1.5.6" "1.5.5" "1.5.4" "1.5.3" "1.5.2" "1.5.1" "1.5.0" 
    "1.4.4" "1.4.3" "1.4.2" "1.4.1" "1.4.0" "1.3.0" "1.2.3" "1.2.2" 
    "1.2.1" "1.2.0" "1.1.0" "1.0.2" "1.0.1" "1.0.0" "0.5.3" 
    "0.5.2" "0.5.0" "0.4.1" "0.4.0" "0.3.3" "0.3.2" "0.3.1" 
    "0.3.0" "0.2.1" "0.2.0"  "0.1.5" "0.1.4" "0.1.3" "0.1.2" 
    "0.1.1" "0.1.0"
    ];

  nativeBuildInputs = [ cargo ];
  buildInputs = [ postgresql ];
  
  CARGO="${cargo}/bin/cargo";
  env = lib.optionalAttrs stdenv.isDarwin {
    POSTGRES_LIB = "${postgresql}/lib";
    RUSTFLAGS = "-C link-arg=-undefined -C link-arg=dynamic_lookup";
  };
  cargoHash = "sha256-WkHufMw8OvinMRYd06ZJACnVvY9OLi069nCgq3LSmMY=";

  # FIXME (aseipp): disable the tests since they try to install .control
  # files into the wrong spot, aside from that the one main test seems
  # to work, though
  doCheck = false;

  preBuild = ''
    echo "Processing git tags..."
    echo '${builtins.concatStringsSep "," previousVersions}' | sed 's/,/\n/g' > git_tags.txt
  '';

  postInstall = ''
    echo "Creating SQL files for previous versions..."
    current_version="${version}"
    sql_file="$out/share/postgresql/extension/pg_graphql--$current_version.sql"
    
    if [ -f "$sql_file" ]; then
      while read -r previous_version; do
        if [ "$(printf '%s\n' "$previous_version" "$current_version" | sort -V | head -n1)" = "$previous_version" ] && [ "$previous_version" != "$current_version" ]; then
          new_file="$out/share/postgresql/extension/pg_graphql--$previous_version--$current_version.sql"
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
    description = "GraphQL support for PostreSQL";
    homepage = "https://github.com/supabase/${pname}";
    maintainers = with maintainers; [ samrose ];
    platforms = postgresql.meta.platforms;
    license = licenses.postgresql;
  };
}
