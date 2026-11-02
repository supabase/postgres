{
  fetchFromGitHub,
  lib,
  pgbackrest,
  python3,
  stdenv,
  systemdLibs,
}:
pgbackrest.overrideAttrs (
  finalAttrs: prevAttrs: {
    version = "2.60.0";

    src = fetchFromGitHub {
      owner = "pgbackrest";
      repo = "pgbackrest";
      rev = "release/${finalAttrs.version}";
      hash = "sha256-3CpKpkCA41OfdwBXBD8MUmypA+eVH3s4BL7ezzH9PqI=";
    };

    # 2.60.0 generates code at build time with build/build.py, which needs PyYAML
    # (only the meson dist tarball ships pre-generated files). Put it ahead of the
    # base python3 so meson and patchShebangs pick it up.
    nativeBuildInputs = [
      (python3.withPackages (ps: [ ps.pyyaml ]))
    ]
    ++ (prevAttrs.nativeBuildInputs or [ ]);

    postPatch = (prevAttrs.postPatch or "") + ''
      patchShebangs build/build.py
    '';

    # 2.59.0 adds an optional libsystemd dependency for systemd notify support.
    # Nonexistent on darwin.
    buildInputs =
      (prevAttrs.buildInputs or [ ]) ++ lib.optional stdenv.hostPlatform.isLinux systemdLibs;
    mesonFlags = (prevAttrs.mesonFlags or [ ]) ++ [
      (lib.mesonEnable "libsystemd" stdenv.hostPlatform.isLinux)
    ];
  }
)
