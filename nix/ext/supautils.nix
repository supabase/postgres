{
  pkgs,
  lib,
  stdenv,
  fetchFromGitHub,
  postgresql,
}:
let
  pname = "supautils";
  # Load version configuration from external file
  allVersions = (builtins.fromJSON (builtins.readFile ./versions.json)).${pname};

  # Filter versions compatible with current PostgreSQL version
  supportedVersions = lib.filterAttrs (
    _: value: builtins.elem (lib.versions.major postgresql.version) value.postgresql
  ) allVersions;

  # Derived version information
  versions = lib.naturalSort (lib.attrNames supportedVersions);
  latestVersion = lib.last versions;
  numberOfVersions = builtins.length versions;
  packages = builtins.attrValues (
    lib.mapAttrs (name: value: build name value.hash) supportedVersions
  );

  # Build function for individual versions
  build =
    version: hash:
    stdenv.mkDerivation rec {
      inherit pname version;

      buildInputs = [ postgresql ];

      src = fetchFromGitHub {
        owner = "supabase";
        repo = pname;
        rev = "refs/tags/v${version}";
        inherit hash;
      };

      installPhase = ''
        runHook preInstall

        mkdir -p $out/{lib,share/postgresql/extension}

        # Install shared library with version suffix
        mv ${pname}${postgresql.dlSuffix} $out/lib/${pname}-${version}${postgresql.dlSuffix}

        # Create version-specific control file
        cat <<EOF > $out/share/postgresql/extension/${pname}--${version}.control
        module_pathname = '$libdir/supautils'
        relocatable = false
        EOF

        runHook postInstall
      '';

      meta = with lib; {
        description = "PostgreSQL extension for enhanced security";
        homepage = "https://github.com/supabase/${pname}";
        maintainers = with maintainers; [ steve-chavez ];
        inherit (postgresql.meta) platforms;
        license = licenses.postgresql;
      };
    };
in
pkgs.buildEnv {
  name = pname;
  paths = packages;
  pathsToLink = [
    "/lib"
    "/share/postgresql/extension"
  ];
  postBuild = ''
    # Create symlinks to latest version for library and control file
    ln -sfn ${pname}-${latestVersion}${postgresql.dlSuffix} $out/lib/${pname}${postgresql.dlSuffix}

    # Create default control file pointing to latest
    {
      echo "default_version = '${latestVersion}'"
      cat $out/share/postgresql/extension/${pname}--${latestVersion}.control
    } > $out/share/postgresql/extension/${pname}.control
  '';

  passthru = {
    inherit versions numberOfVersions;
    pname = "${pname}-all";
    defaultSettings = {
      session_preload_libraries = "supautils";
      "supautils.disable_program" = "true";
      "supautils.privileged_role" = "privileged_role";
    };
    version =
      "multi-" + lib.concatStringsSep "-" (map (v: lib.replaceStrings [ "." ] [ "-" ] v) versions);
  };
}
