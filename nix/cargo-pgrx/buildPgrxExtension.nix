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
{
  lib,
  cargo-pgrx,
  craneLib ? null,
  pkg-config,
  rustPlatform,
  stdenv,
  writeShellScriptBin,
  defaultBindgenHook,
}:

# Unified pgrx extension builder supporting both rustPlatform and crane.
# When craneLib is provided, uses crane for better incremental builds and caching.
# Otherwise falls back to rustPlatform.buildRustPackage.
#
# Crane separates dependency builds from main crate builds, enabling better caching.
# Both approaches accept the same arguments and produce compatible outputs.
#
# IMPORTANT: External Cargo.lock files are handled by extensions' postPatch phases,
# not by copying during evaluation. This avoids IFD (Import From Derivation) issues
# that caused cross-compilation failures when evaluating aarch64 packages on x86_64.
#
# Additional arguments:
#   - `postgresql` postgresql package of the version of postgresql this extension should be build for.
#                  Needs to be the build platform variant.
#   - `useFakeRustfmt` Whether to use a noop fake command as rustfmt. cargo-pgrx tries to call rustfmt.
#                      If the generated rust bindings aren't needed to use the extension, its a
#                      unnecessary and heavy dependency. If you set this to true, you also
#                      have to add `rustfmt` to `nativeBuildInputs`.

{
  buildAndTestSubdir ? null,
  buildType ? "release",
  buildFeatures ? [ ],
  cargoBuildFlags ? [ ],
  postgresql,
  # enable override to generate bindings using bindgenHook.
  # Some older versions of cargo-pgrx use a bindgenHook that is not compatible with the
  # current clang version present in stdenv
  bindgenHook ? defaultBindgenHook,
  # cargo-pgrx calls rustfmt on generated bindings, this is not strictly necessary, so we avoid the
  # dependency here. Set to false and provide rustfmt in nativeBuildInputs, if you need it, e.g.
  # if you include the generated code in the output via postInstall.
  useFakeRustfmt ? true,
  usePgTestCheckFeature ? true,
  ...
}@args:
let
  rustfmtInNativeBuildInputs = lib.lists.any (dep: lib.getName dep == "rustfmt") (
    args.nativeBuildInputs or [ ]
  );
in

assert lib.asserts.assertMsg (
  (args.installPhase or "") == ""
) "buildPgrxExtensions overwrites the installPhase, so providing one does nothing";
assert lib.asserts.assertMsg (
  (args.buildPhase or "") == ""
) "buildPgrxExtensions overwrites the buildPhase, so providing one does nothing";
assert lib.asserts.assertMsg (useFakeRustfmt -> !rustfmtInNativeBuildInputs)
  "The parameter useFakeRustfmt is set to true, but rustfmt is included in nativeBuildInputs. Either set useFakeRustfmt to false or remove rustfmt from nativeBuildInputs.";
assert lib.asserts.assertMsg (!useFakeRustfmt -> rustfmtInNativeBuildInputs)
  "The parameter useFakeRustfmt is set to false, but rustfmt is not included in nativeBuildInputs. Either set useFakeRustfmt to true or add rustfmt from nativeBuildInputs.";

let
  fakeRustfmt = writeShellScriptBin "rustfmt" ''
    exit 0
  '';

  # Rustc wrapper for pgrx < 0.12.0 to filter out empty postmaster_stub.rs arguments
  # This fixes an issue that causes build failures.
  # Fixed upstream in pgcentralfoundation/pgrx#1435 and #1441, available from pgrx >= 0.12.
  rustcWrapper = writeShellScriptBin "rustc" ''
    # ORIGINAL_RUSTC is set in the buildPhase before this wrapper is added to PATH
    original_rustc="''${ORIGINAL_RUSTC:-rustc}"
    filtered_args=()
    for arg in "$@"; do
      if [[ -z "$arg" ]]; then
        continue
      fi
      if [[ "$arg" =~ postmaster_stub\.rs$ ]]; then
        if [[ ! -s "$arg" ]]; then
          continue
        fi
      fi
      filtered_args+=("$arg")
    done
    exec "$original_rustc" "''${filtered_args[@]}"
  '';
  maybeDebugFlag = lib.optionalString (buildType != "release") "--debug";
  maybeEnterBuildAndTestSubdir = lib.optionalString (buildAndTestSubdir != null) ''
    export CARGO_TARGET_DIR="$(pwd)/target"
    pushd "${buildAndTestSubdir}"
  '';
  maybeLeaveBuildAndTestSubdir = lib.optionalString (buildAndTestSubdir != null) "popd";
  pgrxBinaryName = if builtins.compareVersions "0.7.4" cargo-pgrx.version >= 0 then "pgx" else "pgrx";

  # The rustc wrapper is only needed for pgrx < 0.12.0
  # fixed upstream in pgcentralfoundation/pgrx#1435 and #1441
  needsRustcWrapper = builtins.compareVersions cargo-pgrx.version "0.12.0" < 0;

  pgrxPostgresMajor = lib.versions.major postgresql.version;
  preBuildAndTest = ''
    export PGRX_HOME=$(mktemp -d)
    export PGX_HOME=$PGRX_HOME
    export PGDATA="$PGRX_HOME/data-${pgrxPostgresMajor}/"
    cargo-${pgrxBinaryName} ${pgrxBinaryName} init "--pg${pgrxPostgresMajor}" ${lib.getDev postgresql}/bin/pg_config

    # unix sockets work in sandbox, too.
    export PGHOST="$(mktemp -d)"
    cat > "$PGDATA/postgresql.conf" <<EOF
    listen_addresses = '''
    unix_socket_directories = '$PGHOST'
    EOF

    # This is primarily for Mac or other Nix systems that don't use the nixbld user.
    export USER="$(whoami)"
    pg_ctl start
    createuser -h localhost --superuser --createdb "$USER" || true
    pg_ctl stop
  '';

  # Crane-specific: Determine if we're using crane and handle cargo lock info
  # Note: External lockfiles are handled by extensions' postPatch, not here, to avoid
  # creating platform-specific derivations during evaluation (prevents IFD issues)
  useCrane = craneLib != null;
  cargoLockInfo = args.cargoLock or null;

  # External Cargo.lock files are handled by the extension's postPatch phase
  # which creates symlinks. Crane finds them during build, not evaluation.
  # This approach prevents IFD cross-compilation issues.

  # Handle git dependencies based on build system
  cargoVendorDir =
    if useCrane && cargoLockInfo != null then
      # For crane, use vendorCargoDeps with external Cargo.lock file
      craneLib.vendorCargoDeps {
        src = args.src;
        cargoLock = cargoLockInfo.lockFile;
      }
    else
      null;

  # Remove rustPlatform-specific args and pgrx-specific args.
  # For crane, also remove build/install phases (added back later).
  argsForBuilder = builtins.removeAttrs args (
    [
      "postgresql"
      "useFakeRustfmt"
      "usePgTestCheckFeature"
    ]
    ++ lib.optionals useCrane [
      "cargoHash" # rustPlatform uses this, crane uses Cargo.lock directly
      "cargoLock" # handled separately via modifiedSrc and cargoVendorDir
      "installPhase" # we provide our own pgrx-specific install phase
      "buildPhase" # we provide our own pgrx-specific build phase
    ]
  );

  # Common arguments for both rustPlatform and crane
  commonArgs =
    argsForBuilder
    // {
      src = args.src; # Use original source - extensions handle external lockfiles via postPatch
      strictDeps = true;

      buildInputs = (args.buildInputs or [ ]);

      nativeBuildInputs =
        (args.nativeBuildInputs or [ ])
        ++ [
          cargo-pgrx
          postgresql
          pkg-config
          bindgenHook
        ]
        ++ lib.optionals useFakeRustfmt [ fakeRustfmt ];

      PGRX_PG_SYS_SKIP_BINDING_REWRITE = "1";
      CARGO_BUILD_INCREMENTAL = "false";
      RUST_BACKTRACE = "full";

      checkNoDefaultFeatures = true;
      checkFeatures =
        (args.checkFeatures or [ ])
        ++ (lib.optionals usePgTestCheckFeature [ "pg_test" ])
        ++ [ "pg${pgrxPostgresMajor}" ];
    }
    // lib.optionalAttrs (cargoVendorDir != null) {
      inherit cargoVendorDir;
    };

  # Shared build and install phases for both rustPlatform and crane
  sharedBuildPhase = ''
    runHook preBuild

    ${preBuildAndTest}
    ${maybeEnterBuildAndTestSubdir}

    export PGRX_BUILD_FLAGS="--frozen -j $NIX_BUILD_CORES ${builtins.concatStringsSep " " cargoBuildFlags}"
    export PGX_BUILD_FLAGS="$PGRX_BUILD_FLAGS"

    ${lib.optionalString needsRustcWrapper ''
      export ORIGINAL_RUSTC="$(command -v ${stdenv.cc.targetPrefix}rustc || command -v rustc)"
      export PATH="${rustcWrapper}/bin:$PATH"
      export RUSTC="${rustcWrapper}/bin/rustc"
    ''}

    ${lib.optionalString stdenv.hostPlatform.isDarwin ''RUSTFLAGS="''${RUSTFLAGS:+''${RUSTFLAGS} }-Clink-args=-Wl,-undefined,dynamic_lookup"''} \
    cargo ${pgrxBinaryName} package \
      --pg-config ${lib.getDev postgresql}/bin/pg_config \
      ${maybeDebugFlag} \
      --features "${builtins.concatStringsSep " " buildFeatures}" \
      --out-dir "$out"

    ${maybeLeaveBuildAndTestSubdir}

    runHook postBuild
  '';

  sharedInstallPhase = ''
    runHook preInstall

    ${maybeEnterBuildAndTestSubdir}

    cargo-${pgrxBinaryName} ${pgrxBinaryName} stop all

    mv $out/${postgresql}/* $out
    mv $out/${postgresql.lib}/* $out
    rm -rf $out/nix

    ${maybeLeaveBuildAndTestSubdir}

    runHook postInstall
  '';

  # Arguments for rustPlatform.buildRustPackage
  rustPlatformArgs = commonArgs // {
    buildPhase = sharedBuildPhase;
    installPhase = sharedInstallPhase;
    preCheck = preBuildAndTest + args.preCheck or "";
  };

  # Crane's two-phase build: first build dependencies, then build the extension.
  # buildDepsOnly creates a derivation containing only Cargo dependency artifacts.
  # This is cached separately, so changing extension code doesn't rebuild dependencies.
  cargoArtifacts =
    if useCrane then
      craneLib.buildDepsOnly (
        commonArgs
        // {
          pname = "${args.pname or "pgrx-extension"}-deps";

          # pgrx-pg-sys needs PGRX_HOME during dependency build
          preBuild = ''
            ${preBuildAndTest}
            ${maybeEnterBuildAndTestSubdir}
          ''
          + (args.preBuild or "");

          postBuild = ''
            ${maybeLeaveBuildAndTestSubdir}
          ''
          + (args.postBuild or "");

          # Dependencies don't have a postInstall phase
          postInstall = "";

          # Need to specify PostgreSQL version feature for pgrx dependencies
          # and disable default features to avoid multiple pg version conflicts
          cargoExtraArgs = "--no-default-features --features ${
            builtins.concatStringsSep "," ([ "pg${pgrxPostgresMajor}" ] ++ buildFeatures)
          }";
        }
      )
    else
      null;

  # Arguments for crane.buildPackage
  craneArgs = commonArgs // {
    inherit cargoArtifacts;
    pname = args.pname or "pgrx-extension";

    # Explicitly preserve postInstall from args (needed for version-specific file renaming)
    postInstall = args.postInstall or "";

    # We handle installation ourselves via pgrx, don't let crane try to install binaries
    doNotInstallCargoBinaries = true;
    doNotPostBuildInstallCargoBinaries = true;

    buildPhase = sharedBuildPhase;
    installPhase = sharedInstallPhase;
    preCheck = preBuildAndTest + args.preCheck or "";
  };
in
if useCrane then craneLib.buildPackage craneArgs else rustPlatform.buildRustPackage rustPlatformArgs
