{
  lib,
  stdenv,
  writeShellApplication,
  packer,
  awscli2,
  jq,
  ...
}:

let
  root = ../..;
  packerSources = stdenv.mkDerivation {
    name = "packer-sources";
    src = lib.fileset.toSource {
      inherit root;
      fileset = lib.fileset.unions [
        (root + "/ebssurrogate")
        (root + "/ansible")
        (root + "/migrations")
        (root + "/scripts")
        (root + "/amazon-arm64-nix.pkr.hcl")
        (root + "/development-arm.vars.pkr.hcl")
        (lib.fileset.maybeMissing (root + "/common-nix.vars.pkr.hcl"))
      ];
    };

    phases = [
      "unpackPhase"
      "installPhase"
    ];
    installPhase = ''
      mkdir -p $out
      cp -r . $out/
    '';
  };
in
writeShellApplication {
  name = "build-ami";

  runtimeInputs = [
    packer
    awscli2
    jq
  ];

  text = ''
    set -euo pipefail

    set -x

    # Parse stage parameter
    STAGE="''${1:-stage1}"
    shift || true  # Remove first arg, ignore error if no args

    REGION="''${AWS_REGION:-ap-southeast-1}"
    PACKER_SOURCES="${packerSources}"
    INPUT_HASH=$(basename "$PACKER_SOURCES" | cut -d- -f1)

    find_stage1_ami() {
      set +e
      local ami_output
      ami_output=$(aws ec2 describe-images \
        --region "$REGION" \
        --owners self \
        --filters \
          "Name=tag:inputHash,Values=$INPUT_HASH" \
          "Name=tag:postgresVersion,Values=$POSTGRES_VERSION-stage1" \
          "Name=state,Values=available" \
        --query 'Images[0].ImageId' \
        --output text 2>&1)
      local exit_code=$?
      set -e

      if [ $exit_code -ne 0 ] && [ $exit_code -ne 255 ]; then
        echo "Error querying AWS: $ami_output"
        exit 1
      fi

      if [ "$ami_output" = "None" ] || [ -z "$ami_output" ]; then
        echo ""
      else
        echo "$ami_output"
      fi
    }

    if [ "$STAGE" = "stage1" ]; then
      echo "Building stage 1..."
      echo "Checking for existing AMI..."

      AMI_ID=$(find_stage1_ami)
      if [ -n "$AMI_ID" ]; then
        echo "Found existing AMI: $AMI_ID"
        echo "STAGE1_AMI_ID=$AMI_ID"

        if [ -n "''${GITHUB_OUTPUT:-}" ]; then
          AMI_NAME=$(aws ec2 describe-images \
            --region "$REGION" \
            --image-ids "$AMI_ID" \
            --query 'Images[0].Name' \
            --output text)

          if [ -n "$AMI_NAME" ]; then
            echo "::notice title=Stage 1 AMI Found::AMI '$AMI_NAME' (ID: $AMI_ID) found in region $REGION"
          fi
        fi

        exit 0
      fi

      echo "No cached AMI found"

      cd "$PACKER_SOURCES"
      packer init amazon-arm64-nix.pkr.hcl
      packer build \
        -var-file="development-arm.vars.pkr.hcl" \
        -var "input-hash=$INPUT_HASH" \
        -var "postgres-version=$POSTGRES_VERSION" \
        -var "region=$REGION" \
        "$@"

      if [ -n "''${GITHUB_OUTPUT:-}" ]; then
        STAGE1_AMI_ID=$(find_stage1_ami)
        if [ -n "$STAGE1_AMI_ID" ]; then
          AMI_NAME=$(aws ec2 describe-images \
            --region "$REGION" \
            --image-ids "$STAGE1_AMI_ID" \
            --query 'Images[0].Name' \
            --output text)

          if [ -n "$AMI_NAME" ]; then
            echo "::notice title=Stage 1 AMI Built::AMI '$AMI_NAME' (ID: $STAGE1_AMI_ID) built in region $REGION"
          fi
        fi
      fi
    elif [ "$STAGE" = "stage2" ]; then
      echo "Building stage 2..."

      STAGE1_AMI_ID=$(find_stage1_ami)
      if [ -z "$STAGE1_AMI_ID" ]; then
        echo "Error: Stage 1 AMI not found. Please build stage 1 first."
        exit 1
      fi

      echo "Found stage 1 AMI: $STAGE1_AMI_ID"

      packer init stage2-nix-psql.pkr.hcl
      packer build \
        -var-file="development-arm.vars.pkr.hcl" \
        -var-file="common-nix.vars.pkr.hcl" \
        -var "source_ami=$STAGE1_AMI_ID" \
        -var "region=$REGION" \
        "$@"

      if [ -n "''${PACKER_EXECUTION_ID:-}" ]; then
        STAGE2_AMI_ID=$(aws ec2 describe-images \
          --region "$REGION" \
          --owners self \
          --filters \
            "Name=tag:packerExecutionId,Values=''${PACKER_EXECUTION_ID}" \
            "Name=state,Values=available" \
          --query 'Images[0].ImageId' \
          --output text)

        if [ -n "$STAGE2_AMI_ID" ] && [ "$STAGE2_AMI_ID" != "None" ]; then
          echo "STAGE2_AMI_ID=$STAGE2_AMI_ID"

          if [ -n "''${GITHUB_OUTPUT:-}" ]; then
            echo "stage2_ami_id=$STAGE2_AMI_ID" >> "$GITHUB_OUTPUT"

            AMI_NAME=$(aws ec2 describe-images \
              --region "$REGION" \
              --image-ids "$STAGE2_AMI_ID" \
              --query 'Images[0].Name' \
              --output text)

            if [ -n "$AMI_NAME" ]; then
              echo "::notice title=Stage 2 AMI Published::AMI '$AMI_NAME' (ID: $STAGE2_AMI_ID) published in region $REGION"
            fi
          fi
        fi
      fi
    else
      echo "Error: Invalid stage '$STAGE'. Must be 'stage1' or 'stage2'"
      exit 1
    fi
  '';

  meta = {
    description = "Build AMI if not cached based on input hash";
    longDescription = ''
      The input hash is computed from all source files that affect the build.
      Before building, we verify the existence of an AMI with the same hash.
      If found, the build is skipped. Otherwise, a new AMI is created and
      tagged with the input hash for future cache hits.
    '';
  };
}
