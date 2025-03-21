{ lib
, buildGoModule
, fetchFromGitHub
, brotli
, libsodium
, installShellFiles
,
}:

let
  walGCommon = { version, vendorHash, sha256, majorVersion }:
    buildGoModule rec {
      pname = "wal-g-${majorVersion}";
      inherit version;

      src = fetchFromGitHub {
        owner = "wal-g";
        repo = "wal-g";
        rev = "v${version}";
        inherit sha256;
      };

      inherit vendorHash;

      nativeBuildInputs = [ installShellFiles ];

      buildInputs = [
        brotli
        libsodium
      ];

      subPackages = [ "main/pg" ];

      tags = [
        "brotli"
        "libsodium"
      ];

      ldflags = [
        "-s"
        "-w"
        "-X github.com/wal-g/wal-g/cmd/pg.walgVersion=${version}"
        "-X github.com/wal-g/wal-g/cmd/pg.gitRevision=${src.rev}"
      ];

      postInstall = ''
        mv $out/bin/pg $out/bin/wal-g-${majorVersion}
        
        # Create version-specific completions
        mkdir -p $out/share/bash-completion/completions
        $out/bin/wal-g-${majorVersion} completion bash > $out/share/bash-completion/completions/wal-g-${majorVersion}
        
        mkdir -p $out/share/zsh/site-functions
        $out/bin/wal-g-${majorVersion} completion zsh > $out/share/zsh/site-functions/_wal-g-${majorVersion}
        
      '';

      meta = with lib; {
        homepage = "https://github.com/wal-g/wal-g";
        license = licenses.asl20;
        description = "Archival restoration tool for PostgreSQL";
        mainProgram = "wal-g-${majorVersion}";
      };
    };
in
{
  # wal-g v2.0.1
  wal-g-2 = walGCommon {
    version = "2.0.1";
    sha256 = "sha256-5mwA55aAHwEFabGZ6c3pi8NLcYofvoe4bb/cFj7NWok=";
    vendorHash = "sha256-BbQuY6r30AkxlCZjY8JizaOrqEBdv7rIQet9KQwYB/g=";
    majorVersion = "2";
  };

  # wal-g v3.0.5
  wal-g-3 = walGCommon {
    version = "3.0.5";
    sha256 = "sha256-wVr0L2ZXMuEo6tc2ajNzPinVQ8ZVzNOSoaHZ4oFsA+U=";
    vendorHash = "sha256-YDLAmRfDl9TgbabXj/1rxVQ052NZDg3IagXVTe5i9dw=";
    majorVersion = "3";
  };
}
