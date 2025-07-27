# preBuildAndTest and some small other bits
# taken from https://github.com/tcdi/pgrx/blob/v0.9.4/nix/extension.nix
# (but now heavily modified)
# which uses MIT License with the following license file
#
# MIT License
#
# Portions Copyright 2019-2021 ZomboDB, LLC.
# Portions Copyright 2021-2022 Technology Concepts & Design, Inc. <support@tcdi.com>.
# All rights reserved.
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

# Build PostgreSQL extensions using the pgrx framework.
#
# Use it mostly like rustPlatform.buildRustPackage and so
# we hand most of the arguments down.
#
# Additional arguments are:
#   - `postgresql` postgresql package of the version of postgresql this extension should be build for.
#                  Needs to be the build platform variant.
#   - `useFakeRustfmt` Whether to use a noop fake command as rustfmt. cargo-pgrx tries to call rustfmt.
#                      If the generated rust bindings aren't needed to use the extension, its a
#                      unnecessary and heavy dependency. If you set this to true, you also
#                      have to add `rustfmt` to `nativeBuildInputs`.
{
  lib,
  pkg-config,
  stdenv,
  darwin,
  writeShellScriptBin,
  pgrxVersion,
  rustVersion,
  pkgs,
  makeRustPlatform,
  rust-bin,
}:

{
  buildAndTestSubdir ? null,
  buildType ? "release",
  buildFeatures ? [ ],
  cargoBuildFlags ? [ ],
  postgresql,
  useFakeRustfmt ? true,
  usePgTestCheckFeature ? true,
  ...
}@args:

let
  rustPlatform = makeRustPlatform {
    cargo = rust-bin.stable.${rustVersion}.default;
    rustc = rust-bin.stable.${rustVersion}.default;
  };

  versions = builtins.fromJSON (builtins.readFile ./versions.json);
  pgrx = versions.${pgrxVersion};
  cargoHash = pgrx.rust."${rustVersion}".cargoHash;
  cargoVersion = rustVersion;

  rustfmtInNativeBuildInputs = lib.lists.any (dep: lib.getName dep == "rustfmt") (
    args.nativeBuildInputs or [ ]
  );

  cargo-pgrx = pkgs.callPackage ./pgrx.nix {
    inherit cargoHash;
    pgrxHash = pgrx.hash;
    inherit pgrxVersion;
    inherit cargoVersion;
  };
  fakeRustfmt = writeShellScriptBin "rustfmt" "exit 0";
  pgrxPostgresMajor = lib.versions.major postgresql.version;

  setupPgrxEnvironment = ''
        echo "=== Setting up PGRX environment ==="
        export PGRX_HOME=$(mktemp -d)
        export PGDATA="$PGRX_HOME/data-${pgrxPostgresMajor}/"
        export PATH="${postgresql}/bin:$PATH"
        
        cat > $PGRX_HOME/config.toml << EOF
    [configs]
    pg${pgrxPostgresMajor} = "${postgresql}/bin/pg_config"
    EOF
        
        echo "Initializing PGRX..."
        ${cargo-pgrx}/bin/cargo-pgrx pgrx init "--pg${pgrxPostgresMajor}" ${lib.getDev postgresql}/bin/pg_config
  '';

  setupPostgreSQLForTesting = ''
    echo "=== Setting up PostgreSQL for extension testing ==="
    export PGHOST="$(mktemp -d)"
    export USER="$(whoami)"

    echo "Starting PostgreSQL..."
    pg_ctl start -w -l "$PGDATA/postgresql.log" || {
      echo "PostgreSQL failed to start, continuing without database (package-only build)..."
    }

    if pg_ctl status >/dev/null 2>&1; then
      createuser -h localhost --superuser --createdb "$USER" 2>/dev/null || true
    fi
  '';

  buildExtensionPhase = ''
    echo "=== Building extension with cargo-pgrx ==="

    ${lib.optionalString (buildAndTestSubdir != null) ''
      export CARGO_TARGET_DIR="$(pwd)/target"
      pushd "${buildAndTestSubdir}"
    ''}

    PGRX_BUILD_FLAGS="--frozen -j $NIX_BUILD_CORES ${builtins.concatStringsSep " " cargoBuildFlags}"

    ${lib.optionalString stdenv.hostPlatform.isDarwin ''
      export RUSTFLAGS="''${RUSTFLAGS:+''${RUSTFLAGS} }-Clink-args=-Wl,-undefined,dynamic_lookup"
    ''}

    ${cargo-pgrx}/bin/cargo-pgrx pgrx package \
      --pg-config ${lib.getDev postgresql}/bin/pg_config \
      ${lib.optionalString (buildType != "release") "--debug"} \
      ${
        lib.optionalString (
          buildFeatures != [ ]
        ) "--features \"${builtins.concatStringsSep " " buildFeatures}\""
      } \
      --out-dir "$out"

    ${lib.optionalString (buildAndTestSubdir != null) "popd"}
  '';

  cleanupPhase = ''
    echo "=== Cleaning up PostgreSQL ==="
    if [ -n "''${PGDATA:-}" ] && [ -f "$PGDATA/postmaster.pid" ]; then
      echo "Stopping PostgreSQL..."
      pg_ctl stop -w || true
    fi
  '';
in

assert lib.asserts.assertMsg (
  (args.installPhase or "") == ""
) "buildPgrxExtensions overwrites the installPhase";

assert lib.asserts.assertMsg (
  (args.buildPhase or "") == ""
) "buildPgrxExtensions overwrites the buildPhase";

assert lib.asserts.assertMsg (
  useFakeRustfmt -> !rustfmtInNativeBuildInputs
) "useFakeRustfmt conflicts with rustfmt in nativeBuildInputs";

assert lib.asserts.assertMsg (
  !useFakeRustfmt -> rustfmtInNativeBuildInputs
) "useFakeRustfmt false but no rustfmt in nativeBuildInputs";

rustPlatform.buildRustPackage (
  builtins.removeAttrs args [
    "postgresql"
    "useFakeRustfmt"
    "usePgTestCheckFeature"
  ]
  // {
    buildInputs =
      (args.buildInputs or [ ])
      ++ lib.optionals stdenv.hostPlatform.isDarwin [ darwin.apple_sdk.frameworks.Security ];

    nativeBuildInputs =
      (args.nativeBuildInputs or [ ])
      ++ [
        cargo-pgrx
        postgresql
        pkg-config
        rustPlatform.bindgenHook
      ]
      ++ lib.optionals useFakeRustfmt [ fakeRustfmt ];

    buildPhase = ''
      runHook preBuild

      ${setupPgrxEnvironment}  
      ${setupPostgreSQLForTesting}
      ${buildExtensionPhase}

      runHook postBuild
    '';

    installPhase = ''
      runHook preInstall

      ${lib.optionalString (buildAndTestSubdir != null) ''
        pushd "${buildAndTestSubdir}"
      ''}

      echo "=== Installing extension files ==="

      mv $out/${postgresql}/* $out
      mv $out/${postgresql.lib}/* $out  
      rm -rf $out/nix

      ${lib.optionalString (buildAndTestSubdir != null) "popd"}

      runHook postInstall
    '';

    postBuild = cleanupPhase;
    postInstall = cleanupPhase;

    PGRX_PG_SYS_SKIP_BINDING_REWRITE = "1";
    CARGO_BUILD_INCREMENTAL = "false";
    RUST_BACKTRACE = "full";

    checkNoDefaultFeatures = true;
    checkFeatures =
      (args.checkFeatures or [ ])
      ++ lib.optionals usePgTestCheckFeature [ "pg_test" ]
      ++ [ "pg${pgrxPostgresMajor}" ];

    meta = (args.meta or { }) // {
      description = args.meta.description or "PostgreSQL extension built with pgrx";
      platforms = lib.platforms.unix;
    };
  }
)
