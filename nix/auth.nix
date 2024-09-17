{ lib
, buildGoModule
, fetchFromGitHub
, go_1_22
}:

let
  go_1_22_3 = go_1_22.overrideAttrs (oldAttrs: rec {
    version = "1.22.3";
    src = fetchFromGitHub {
      owner = "golang";
      repo = "go";
      rev = "go${version}";
      hash = "sha256-idGXPf199JX6H5WPPalcoW2gS0QBT5YEsndBqEcUBgs=";
    };
  });
in
buildGoModule rec {
  pname = "auth";
  version = "2.160.0";

  src = fetchFromGitHub {
    owner = "supabase";
    repo = "auth";
    rev = "v${version}";
    hash = "sha256-29mTu3Cv3rFsm9q79g2BBzRLWfA9WlBip8xbBROCCzo=";
  };

  vendorHash = "sha256-cxLN9bdtpZmnhhP9tIYHQXW+KVmKvbS5+j+0gN6Ml3s=";

  ldflags = [
    "-s"
    "-w"
    "-X github.com/supabase/auth/internal/utilities.Version=${version}"
  ];

  doCheck = false;

  # Force the use of Go 1.22.3
  #nativeBuildInputs = [ go_1_22_3 ];
  buildInputs = [ go_1_22_3 ];

  # Override the go command used by buildGoModule
  preBuild = ''
    export GOROOT=${go_1_22_3}/share/go
    export PATH=${go_1_22_3}/bin:$PATH
  '';

  # Ensure Go 1.22.3 is used for all Go commands
  GO = "${go_1_22_3}/bin/go";

  meta = with lib; {
    homepage = "https://github.com/supabase/auth";
    description = "JWT based API for managing users and issuing JWT tokens";
    mainProgram = "auth";
    changelog = "https://github.com/supabase/auth/releases/tag/v${version}";
    license = licenses.mit;
    maintainers = with maintainers; [ samrose ];
  };
}

