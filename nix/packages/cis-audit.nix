{
  pkgs,
  lib,
  inputs,
}:
let
  # Use Go 1.24 for the scanner which requires Go >= 1.23.2
  go124 = inputs.nixpkgs-go124.legacyPackages.${pkgs.system}.go_1_24;
  buildGoModule124 = pkgs.buildGoModule.override { go = go124; };

  # Package GOSS - server validation spec runner
  goss = pkgs.buildGoModule rec {
    pname = "goss";
    version = "0.4.8";
    src = pkgs.fetchFromGitHub {
      owner = "goss-org";
      repo = "goss";
      rev = "v${version}";
      hash = "sha256-xabGzCTzWwT8568xg6sdlE32OYPXlG9Fei0DoyAoXgo=";
    };
    vendorHash = "sha256-BPW4nC9gxDbyhA5UOfFAtOIusNvwJ7pQiprZsqTiak0=";
  };

  # CIS audit specifications bundled as a package
  cisAuditSpecs = pkgs.stdenv.mkDerivation {
    name = "cis-audit-specs";
    src = ../../audit-specs;
    installPhase = ''
      mkdir -p $out/share/cis-audit
      cp -r * $out/share/cis-audit/
    '';
  };

  # Main audit CLI wrapper
  cis-audit = pkgs.writeScriptBin "cis-audit" ''
    #!${pkgs.bash}/bin/bash
    set -euo pipefail

    SPEC_FILE=""
    LEVEL=""
    PROFILE=""
    OUTPUT_FORMAT="tap"
    LIST_SPECS=false

    usage() {
      cat << EOF
    CIS Ubuntu Audit Tool

    Usage: cis-audit [OPTIONS]

    Options:
      -s, --spec        Use a specific spec file (e.g., baselines/baseline.yml)
      -l, --level       CIS level 1 or 2 (default: 1)
      -p, --profile     server or workstation (default: server)
      -f, --format      Output format: tap, documentation, json, junit, nagios, silent (default: tap)
      --list            List all available spec files
      --help            Show this help

    Examples:
      # Use a committed baseline
      cis-audit --spec baselines/baseline.yml

      # Use pre-defined CIS benchmark
      cis-audit --level 1 --profile server

      # List available specs
      cis-audit --list

      # Custom format
      cis-audit --spec baselines/postgres-baseline.yml --format json
    EOF
    }

    # Argument parsing
    while [[ $# -gt 0 ]]; do
      case $1 in
        -s|--spec)
          SPEC_FILE="$2"
          shift 2
          ;;
        -l|--level)
          LEVEL="$2"
          shift 2
          ;;
        -p|--profile)
          PROFILE="$2"
          shift 2
          ;;
        -f|--format)
          OUTPUT_FORMAT="$2"
          shift 2
          ;;
        --list)
          LIST_SPECS=true
          shift
          ;;
        --help)
          usage
          exit 0
          ;;
        *)
          echo "Unknown option: $1"
          usage
          exit 1
          ;;
      esac
    done

    # Validate output format
    case "$OUTPUT_FORMAT" in
      tap|documentation|json|junit|nagios|silent)
        # Valid format
        ;;
      *)
        echo "Error: Invalid output format: $OUTPUT_FORMAT"
        echo "Valid formats: tap, documentation, json, junit, nagios, silent"
        exit 1
        ;;
    esac

    # List specs if requested
    if [ "$LIST_SPECS" = true ]; then
      echo "Available specification files:"
      echo ""
      echo "CIS Benchmarks:"
      find ${cisAuditSpecs}/share/cis-audit -maxdepth 1 -name "cis_*.yaml" -exec basename {} \; | sort
      echo ""
      echo "Baselines:"
      if [ -d "${cisAuditSpecs}/share/cis-audit/baselines" ]; then
        find ${cisAuditSpecs}/share/cis-audit/baselines -name "*.yml" -o -name "*.yaml" | while read f; do
          basename "$f"
        done | sort
      fi
      exit 0
    fi

    # Determine which spec file to use
    if [ -n "$SPEC_FILE" ]; then
      # Check if file exists locally (absolute or relative path)
      if [ -f "$SPEC_FILE" ]; then
        FULL_SPEC_PATH="$SPEC_FILE"
      # Check if it's a bundled spec
      elif [ -f "${cisAuditSpecs}/share/cis-audit/$SPEC_FILE" ]; then
        FULL_SPEC_PATH="${cisAuditSpecs}/share/cis-audit/$SPEC_FILE"
      else
        # File not found anywhere
        FULL_SPEC_PATH="$SPEC_FILE"
      fi
    else
      # Use level/profile (default to level 1 server)
      LEVEL=''${LEVEL:-1}
      PROFILE=''${PROFILE:-server}
      FULL_SPEC_PATH="${cisAuditSpecs}/share/cis-audit/cis_level''${LEVEL}_''${PROFILE}.yaml"
    fi

    if [[ ! -f "$FULL_SPEC_PATH" ]]; then
      echo "Error: Spec file not found: $FULL_SPEC_PATH"
      echo ""
      echo "Run 'cis-audit --list' to see available specs"
      exit 1
    fi

    echo "Running audit with: $(basename $FULL_SPEC_PATH)"
    echo ""

    # Run GOSS with sudo
    sudo ${goss}/bin/goss --gossfile "$FULL_SPEC_PATH" validate --format "$OUTPUT_FORMAT"
  '';

  # Go-based CIS scanner for generating baseline specs
  cis-generate-spec = buildGoModule124 {
    pname = "cis-generate-spec";
    version = "1.0.0";

    src = ./cis-audit/scanner;

    vendorHash = "sha256-ryZHIucmEce/ciVeJCB08WUY4HsgOTOph+OviwRe/CE=";

    subPackages = [ "cmd/cis-generate-spec" ];

    ldflags = [
      "-s"
      "-w"
      "-X main.version=1.0.0"
    ];

    buildInputs = lib.optionals pkgs.stdenv.isDarwin [
      pkgs.darwin.apple_sdk.frameworks.IOKit
      pkgs.darwin.apple_sdk.frameworks.CoreFoundation
    ];

    doCheck = true;
    checkPhase = ''
      go test -v ./...
    '';

    meta = with lib; {
      description = "CIS security compliance scanner - generates baseline specs";
      license = licenses.asl20;
      platforms = platforms.linux ++ platforms.darwin;
    };
  };

  # Python environment with PyYAML for ansible-to-goss
  pythonWithYaml = pkgs.python3.withPackages (ps: [ ps.pyyaml ]);

  # Python script to convert Ansible playbooks to GOSS specs
  ansible-to-goss = pkgs.writeScriptBin "ansible-to-goss" ''
    #!${pythonWithYaml}/bin/python3
    import yaml
    import sys
    import os
    from pathlib import Path

    def usage():
        print("""
    Ansible to GOSS Converter

    Converts Ansible playbooks and tasks to GOSS specifications.

    Usage: ansible-to-goss <ansible-playbook-dir> [output-file]

    Arguments:
      ansible-playbook-dir - Path to Ansible playbook directory
      output-file         - Output YAML file (default: ansible-baseline.yaml)

    Example:
      ansible-to-goss ./ansible baseline.yaml
      ansible-to-goss /path/to/ansible
    """)

    def parse_ansible_apt(task):
        """Convert Ansible apt tasks to GOSS package specs"""
        packages = []
        if "pkg" in task.get("ansible.builtin.apt", {}):
            pkgs = task["ansible.builtin.apt"]["pkg"]
            if isinstance(pkgs, list):
                packages = pkgs
            elif isinstance(pkgs, str):
                packages = [pkgs]
        elif "name" in task.get("ansible.builtin.apt", {}):
            packages = [task["ansible.builtin.apt"]["name"]]
        elif "pkg" in task.get("apt", {}):
            pkgs = task["apt"]["pkg"]
            if isinstance(pkgs, list):
                packages = pkgs
            elif isinstance(pkgs, str):
                packages = [pkgs]
        return packages

    def parse_ansible_sysctl(task):
        """Convert Ansible sysctl tasks to GOSS kernel-param specs"""
        params = {}
        for module in ["ansible.builtin.sysctl", "ansible.posix.sysctl", "sysctl"]:
            if module in task:
                name = task[module].get("name")
                value = task[module].get("value")
                if name and value is not None:
                    params[name] = str(value)
        return params

    def parse_ansible_systemd(task):
        """Convert Ansible systemd tasks to GOSS service specs"""
        services = {}
        for module in ["ansible.builtin.systemd_service", "ansible.builtin.systemd", "systemd"]:
            if module in task:
                name = task[module].get("name", "").replace(".service", "")
                state = task[module].get("state", "")
                enabled = task[module].get("enabled", None)

                if name:
                    service_spec = {}
                    if enabled is not None:
                        service_spec["enabled"] = enabled
                    if state in ["started", "restarted"]:
                        service_spec["running"] = True
                    elif state == "stopped":
                        service_spec["running"] = False

                    if service_spec:
                        services[name] = service_spec
        return services

    def parse_ansible_file(task):
        """Convert Ansible file/copy tasks to GOSS file specs"""
        files = {}
        for module in ["ansible.builtin.file", "ansible.builtin.copy", "file", "copy"]:
            if module in task:
                path = task[module].get("dest") or task[module].get("path")
                if path:
                    file_spec = {"exists": True}

                    if "mode" in task[module]:
                        mode = task[module]["mode"]
                        if isinstance(mode, str):
                            mode = mode.strip("'\"")
                        file_spec["mode"] = str(mode)

                    if "owner" in task[module]:
                        file_spec["owner"] = task[module]["owner"]

                    if "group" in task[module]:
                        file_spec["group"] = task[module]["group"]

                    files[path] = file_spec
        return files

    def convert_ansible_to_goss(ansible_dir):
        """Main conversion function"""
        goss_spec = {
            "package": {},
            "service": {},
            "kernel-param": {},
            "file": {},
            "command": {}
        }

        # Find all YAML files
        ansible_path = Path(ansible_dir)
        yaml_files = list(ansible_path.glob("**/*.yml")) + list(ansible_path.glob("**/*.yaml"))

        print(f"[*] Found {len(yaml_files)} Ansible files")
        print(f"[*] Processing...")

        for yaml_file in yaml_files:
            try:
                with open(yaml_file, "r") as f:
                    data = yaml.safe_load(f)

                    if not data:
                        continue

                    # Handle playbooks (list of plays)
                    if isinstance(data, list):
                        for play in data:
                            if isinstance(play, dict) and "tasks" in play:
                                for task in play["tasks"]:
                                    process_task(task, goss_spec)
                            elif isinstance(play, dict):
                                # Direct task
                                process_task(play, goss_spec)

                    # Handle task files
                    elif isinstance(data, dict):
                        process_task(data, goss_spec)

            except Exception as e:
                print(f"[!] Warning: Failed to parse {yaml_file}: {e}", file=sys.stderr)
                continue

        # Remove empty sections
        return {k: v for k, v in goss_spec.items() if v}

    def process_task(task, goss_spec):
        """Process a single Ansible task"""
        if not isinstance(task, dict):
            return

        # Extract packages from apt tasks
        packages = parse_ansible_apt(task)
        for pkg in packages:
            goss_spec["package"][pkg] = {"installed": True}

        # Extract sysctl params
        params = parse_ansible_sysctl(task)
        for name, value in params.items():
            goss_spec["kernel-param"][name] = {"value": value}

        # Extract services
        services = parse_ansible_systemd(task)
        for name, spec in services.items():
            if name not in goss_spec["service"]:
                goss_spec["service"][name] = {}
            goss_spec["service"][name].update(spec)

        # Extract files
        files = parse_ansible_file(task)
        for path, spec in files.items():
            goss_spec["file"][path] = spec

    def main():
        if len(sys.argv) < 2 or sys.argv[1] in ["-h", "--help"]:
            usage()
            sys.exit(0 if len(sys.argv) >= 2 else 1)

        ansible_dir = sys.argv[1]
        output_file = sys.argv[2] if len(sys.argv) > 2 else "ansible-baseline.yaml"

        if not os.path.isdir(ansible_dir):
            print(f"Error: Directory not found: {ansible_dir}", file=sys.stderr)
            sys.exit(1)

        print("=" * 60)
        print("Ansible to GOSS Converter")
        print("=" * 60)
        print()
        print(f"Input:  {ansible_dir}")
        print(f"Output: {output_file}")
        print()

        goss_spec = convert_ansible_to_goss(ansible_dir)

        # Add header comments
        header = f"""# GOSS Specification
    # Generated from Ansible playbooks in: {ansible_dir}
    # DO NOT EDIT - Generated by ansible-to-goss

    """

        with open(output_file, "w") as f:
            f.write(header)
            yaml.dump(goss_spec, f, default_flow_style=False, sort_keys=False)

        print()
        print("=" * 60)
        print("Conversion complete!")
        print("=" * 60)
        print()
        print("Statistics:")
        print(f"  Packages: {len(goss_spec.get('package', {}))}")
        print(f"  Services: {len(goss_spec.get('service', {}))}")
        print(f"  Kernel params: {len(goss_spec.get('kernel-param', {}))}")
        print(f"  Files: {len(goss_spec.get('file', {}))}")
        print()
        print(f"Output: {output_file}")
        print()
        print("Review and edit the spec, then use it with:")
        print(f"  goss --gossfile {output_file} validate")

    if __name__ == "__main__":
        main()
  '';
in
{
  inherit
    goss
    cis-audit
    cis-generate-spec
    ansible-to-goss
    ;
  cis-audit-specs = cisAuditSpecs;
}
