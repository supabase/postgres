{ inputs, ... }:
{
  perSystem =
    { system, ... }:
    {
      _module.args.pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        permittedInsecurePackages = [ "v8-9.7.106.18" ];
        overlays = [
          # Patch tzdata to 2026f until nixpkgs catches up.
          # Drop once the pinned nixpkgs ships >= 2026f (the assertion below trips):
          # remove both the tzdata and the vde2 overrides in this overlay.
          #
          # vde2 is only here because of the tzdata override causing wolfssl to be rebuilt.
          # wolfssl's own test suite fails on the CI runners.
          # vde2 only uses wolfssl for vde_cryptcab, which the VM tests don't need, so build vde2 without it.
          (
            final: prev:
            let
              version = "2026f";
            in
            {
              tzdata = prev.tzdata.overrideAttrs (
                old:
                assert final.lib.assertMsg (
                  # Versions are <year><letter>, so plain string ordering is chronological.
                  old.version < version
                ) "nixpkgs tzdata ${old.version} is not older than ${version}; remove the tzdata override";
                {
                  inherit version;
                  # 2026f no longer installs share/zoneinfo-posix or share/zoneinfo-leaps (no more leap seconds)
                  # patch old.postInstall so it doesn't fail when not found
                  postInstall =
                    builtins.replaceStrings
                      [
                        "rm $out/share/zoneinfo-posix\n"
                        "mv $out/share/zoneinfo-leaps $out/share/zoneinfo/right\n"
                      ]
                      [
                        ""
                        ""
                      ]
                      old.postInstall;
                  srcs = [
                    (final.fetchurl {
                      url = "https://data.iana.org/time-zones/releases/tzdata${version}.tar.gz";
                      hash = "sha256-AbSpHOxRZ+1IwR6Kt48gSM6teM6UsMr8rQroxaMETT0=";
                    })
                    (final.fetchurl {
                      url = "https://data.iana.org/time-zones/releases/tzcode${version}.tar.gz";
                      hash = "sha256-WhjaATk2ee8lWSFNxodWP389BWkfb1i3+8AWbz55bNY=";
                    })
                  ];
                }
              );
              # pre-commit's test suite pulls in dotnet-sdk, which depends on tzdata.
              # dotnet-sdk fails to build with
              # > The specified version string '7.1.2.71102' does not conform to the recommended format - major.minor.build.revision
              # 1102 looks like the current date (when CI tried to build and failed...), on 10/31 the revision was 71031.
              pre-commit = prev.pre-commit.overridePythonAttrs {
                doCheck = false;
                preCheck = "";
                # pytestCheckPhase runs as a preDist phase regardless of doCheck, and its
                # flags include --forked (pytest-forked), which isn't available here.
                dontUsePytestCheck = true;
              };
              pythonPackagesExtensions =
                prev.pythonPackagesExtensions
                ++ final.lib.optionals prev.stdenv.hostPlatform.isDarwin [
                  (_pyFinal: pyPrev: {
                    # test_timeout expects regex's timeout= to fire on a busy-wait callback; it doesn't on darwin.
                    backrefs = pyPrev.backrefs.overridePythonAttrs (old: {
                      disabledTests = (old.disabledTests or [ ]) ++ [ "test_timeout" ];
                    });
                    # setproctitle's fork tests segfault on darwin, skip them for now since linux is still good; skip them.
                    setproctitle = pyPrev.setproctitle.overridePythonAttrs { doCheck = false; };
                    uvloop = pyPrev.uvloop.overridePythonAttrs (old: {
                      disabledTests = (old.disabledTests or [ ]) ++ [ "test_cancel_post_init" ];
                    });
                  })
                ];
              # node's test suite fails on darwin
              nodejs = prev.nodejs.overrideAttrs { doCheck = !prev.stdenv.hostPlatform.isDarwin; };
              vde2 = prev.vde2.overrideAttrs (
                old:
                assert final.lib.assertMsg (
                  prev.tzdata.version < version
                ) "nixpkgs tzdata ${prev.tzdata.version} is not older than ${version}; remove the vde2 override";
                {
                  buildInputs = final.lib.remove final.wolfssl old.buildInputs;
                  configureFlags = (old.configureFlags or [ ]) ++ [ "--disable-cryptcab" ];
                }
              );
            }
          )
          (
            let
              # Provide older versions of packages required by some extensions
              oldstable = import inputs.nixpkgs-oldstable {
                inherit system;
                config.allowUnfree = true;
              };
            in
            _final: _prev: {
              v8_oldstable = oldstable.v8;
            }
          )
        ];
      };
    };
}
