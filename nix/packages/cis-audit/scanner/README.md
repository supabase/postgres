# CIS Generate Spec - Go Scanner

High-performance system scanner for CIS security compliance auditing. This tool scans Ubuntu/Debian systems and generates a baseline specification file containing system configuration details for security audit purposes.

## Features

- **Fast Performance**: Implemented in Go for optimal speed and efficiency
- **Flexible Output**: Supports both YAML and JSON formats
- **Comprehensive Scanning**: Captures packages, files, services, users, groups, kernel parameters, and mounts
- **Optional Dynamic Checks**: Can include listening ports and running processes
- **Configurable Exclusions**: Support for excluding specific files, ports, or processes via config file
- **Structured Logging**: JSON or logfmt logging to stderr with verbose/debug modes
- **Error Handling**: Graceful handling of permission errors with optional strict mode

## Installation

### Via Nix (Recommended)

```bash
# Build
nix build .#cis-generate-spec

# Run directly
nix run .#cis-generate-spec -- --help

# Enter dev shell
nix develop
```

### Via Go

```bash
cd scanner
go build -o cis-generate-spec ./cmd/cis-generate-spec
```

## Usage

### Basic Usage

```bash
# Generate default machine-baseline.yaml in current directory
cis-generate-spec

# Specify output file
cis-generate-spec /path/to/output.yaml

# Generate JSON output
cis-generate-spec --format json baseline.json
```

### Advanced Options

```bash
# Include dynamic checks (ports and processes)
cis-generate-spec --include-dynamic --include-ports --include-processes

# Use configuration file for exclusions
cis-generate-spec --config /path/to/cis-config.yaml

# Enable verbose logging to stderr
cis-generate-spec --verbose

# Enable debug logging with JSON format
cis-generate-spec --debug --log-format json

# Strict mode: fail on any access errors
cis-generate-spec --strict
```

### Configuration File

Create a YAML configuration file to exclude specific items:

```yaml
# cis-config.yaml
exclude:
  files:
    - "/proc/*"
    - "/sys/*"
    - "/tmp/*"
  ports:
    - "22"  # SSH
    - "80"  # HTTP
  processes:
    - "systemd"
    - "kernel"
```

Load the config with `--config`:

```bash
cis-generate-spec --config cis-config.yaml --include-dynamic
```

## Output Format

The generated specification file contains:

### Static Resources (Always Included)

- **Packages**: Installed system packages with versions and statuses
- **Files**: File system entries with permissions, ownership, and modes
- **Services**: Systemd services and their enabled/disabled states
- **Users**: System users with UID, shell, and home directory
- **Groups**: System groups with GID and members
- **Kernel Parameters**: Sysctl parameters and their values
- **Mounts**: Mounted filesystems with mount points and options

### Dynamic Resources (Optional)

- **Ports**: Listening network ports (with `--include-ports`)
- **Processes**: Running processes (with `--include-processes`)

### Example Output

```yaml
kind: Package
title: openssh-server
version: 1:8.9p1-3ubuntu0.1
status: install ok installed
---
kind: File
title: /etc/ssh/sshd_config
path: /etc/ssh/sshd_config
mode: "0644"
user: root
group: root
---
kind: Service
title: ssh
unit: ssh.service
enabled: true
---
kind: KernelParameter
title: net.ipv4.ip_forward
value: "0"
```

## Performance

The Go implementation is significantly faster than the previous bash implementation:

- **Typical scan time**: 2-5 seconds on modern systems
- **Memory usage**: ~20-50 MB
- **Concurrent scanning**: Parallel execution where safe

## Development

### Running Tests

```bash
# Run all unit tests
go test ./...

# Run with verbose output
go test -v ./...

# Run specific package tests
go test ./internal/scanners/...

# Via Nix
nix develop -c go test ./...
```

### Project Structure

```
scanner/
├── cmd/
│   └── cis-generate-spec/    # Main CLI entry point
├── internal/
│   ├── config/               # Configuration loading
│   ├── logger/               # Structured logging
│   ├── scanners/             # Scanner implementations
│   └── spec/                 # Output formatting (YAML/JSON)
├── go.mod
└── README.md
```

### Architecture

Each scanner implements the `Scanner` interface:

```go
type Scanner interface {
    Type() string
    Scan(ctx context.Context) ([]Resource, error)
}
```

Scanners run independently and can be composed via `RunAll()`. See `../docs/plans/2025-11-23-go-cis-scanner-design.md` for detailed architecture documentation.

## Known Limitations

- **Requires Root/Sudo**: Many system checks require elevated privileges
- **Linux-specific**: Designed for Ubuntu/Debian systems; may not work on other distributions
- **Dynamic Checks**: Ports and processes are snapshots at scan time and may change
- **Exclusions**: Config file exclusions only apply to files, ports, and processes; not to other resource types

## Troubleshooting

### Permission Errors

If you encounter permission errors:

```bash
# Run with sudo for full system access
sudo cis-generate-spec

# Or use --verbose to see which files are being skipped
cis-generate-spec --verbose
```

### Empty or Incomplete Output

- Verify you're running with sufficient permissions
- Use `--debug` to see detailed execution logs
- Check that systemd is available on the system

### Configuration Not Applied

- Verify YAML syntax in config file
- Use `--verbose` to confirm config file is loaded
- Check that exclusion patterns match actual resource names

## Contributing

This project is part of the Supabase Ubuntu CIS Audit tooling. For design decisions and implementation details, see `../docs/plans/`.

## License

See repository root for license information.
