{
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
  buildEnv,
  lz4,
  patchelf,
  duckdb-lib,
  latestOnly ? false,
}:
let
  pname = "pg_duckdb";
  version = "1.1.1";

  drv = stdenv.mkDerivation {
    inherit pname version;

    src = fetchFromGitHub {
      owner = "TylerHillery";
      repo = "pg_duckdb";
      rev = "eb7af6ede232f951c78192c79109c6d0be73b7b2";
      hash = "sha256-nhnxaesR9IOZWkfUFJ5ds+2OpcstMQ9OpUvsHGqnN7Y=";
    };

    nativeBuildInputs = lib.optionals (!stdenv.isDarwin) [ patchelf ];

    buildInputs = [
      postgresql
      duckdb-lib.lib
      duckdb-lib.dev
      lz4
    ];

    # No configure script — uses PGXS directly via Makefile.global
    dontConfigure = true;

    postPatch = ''
      # The GitHub tarball does not include the third_party/duckdb git submodule.
      # pg_duckdb's Makefile expects DuckDB headers at:
      #   third_party/duckdb/src/include
      #   third_party/duckdb/third_party/re2
      # and the built library at:
      #   third_party/duckdb/build/release/src/libduckdb<ext>
      # We satisfy all three using our pre-built duckdb-lib derivation.

      mkdir -p third_party/duckdb/src
      ln -sf ${duckdb-lib.dev}/include third_party/duckdb/src/include

      # pg_duckdb adds re2 as a system include for warning suppression only;
      # it does not include re2 headers directly.
      mkdir -p third_party/duckdb/third_party/re2

      # Make the pre-built libduckdb visible at the path the Makefile's linker
      # flags expect: -L$(DUCKDB_BUILD_DIR)/src -lduckdb
      # (DUCKDB_BUILD_DIR = third_party/duckdb/build/release)
      mkdir -p third_party/duckdb/build/release/src
      ln -sf ${duckdb-lib.lib}/lib/libduckdb${postgresql.dlSuffix} \
        third_party/duckdb/build/release/src/libduckdb${postgresql.dlSuffix}

      # The Makefile has two separate dependencies on .git/modules/third_party/duckdb/HEAD:
      #   1. $(FULL_DUCKDB_LIB) — recipe overridden to no-op below
      #   2. $(OBJS) — every .o depends on it directly (Makefile:98) to ensure
      #      DuckDB headers are present before compilation.
      # Fake the sentinel so make considers it satisfied without running git.
      mkdir -p .git/modules/third_party/duckdb
      echo "ref: refs/heads/main" > .git/modules/third_party/duckdb/HEAD

      # Override the FULL_DUCKDB_LIB build recipe with a no-op.
      # GNU Make uses the last-defined recipe when a target appears multiple times.
      # This prevents make from invoking cmake/ninja to build DuckDB from source;
      # the pre-built library is already in place via the symlink above.
      printf '\n# Nix override: skip DuckDB cmake build\n$(FULL_DUCKDB_LIB):\n\t@:\n' >> Makefile
    '';

    NIX_LDFLAGS = lib.optionalString stdenv.isDarwin "-headerpad_max_install_names";

    makeFlags = [
      "PG_CONFIG=${postgresql}/bin/pg_config"
    ];

    installPhase = ''
      runHook preInstall
      mkdir -p $out/{lib,share/postgresql/extension}

      install -Dm755 pg_duckdb${postgresql.dlSuffix} $out/lib/pg_duckdb${postgresql.dlSuffix}

      # Fix rpath so pg_duckdb.so finds libduckdb in the Nix store at runtime.
      # PostgreSQL uses dlopen() to load extensions, so the rpath in the .so
      # file must point to an absolute path where libduckdb lives.
      ${lib.optionalString (!stdenv.isDarwin) ''
        ${patchelf}/bin/patchelf \
          --set-rpath "${duckdb-lib.lib}/lib:${postgresql}/lib" \
          $out/lib/pg_duckdb${postgresql.dlSuffix}
      ''}
      ${lib.optionalString stdenv.isDarwin ''
        install_name_tool \
          -add_rpath "${duckdb-lib.lib}/lib" \
          -add_rpath "${postgresql}/lib" \
          $out/lib/pg_duckdb${postgresql.dlSuffix}
      ''}

      cp pg_duckdb.control $out/share/postgresql/extension/
      cp sql/pg_duckdb--*.sql $out/share/postgresql/extension/

      runHook postInstall
    '';

    meta = {
      description = "DuckDB-powered analytical queries inside PostgreSQL";
      homepage = "https://github.com/duckdb/pg_duckdb";
      platforms = postgresql.meta.platforms;
      license = lib.licenses.mit;
    };
  };
in
buildEnv {
  name = pname;
  paths = [ drv ];
  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];

  passthru = {
    inherit pname version latestOnly;
  };
}
