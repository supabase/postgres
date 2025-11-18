# Local AMI Development with pg-ami-builder

This guide explains how to use `pg-ami-builder` for local AMI development and iteration.

## Prerequisites

### Required Tools

- AWS CLI v2
- aws-vault (for credential management)
- SSM Session Manager plugin
- Git
- Nix

### Installing SSM Session Manager Plugin

**macOS:**
```bash
brew install --cask session-manager-plugin
```

**Linux:**
See [AWS documentation](https://docs.aws.amazon.com/systems-manager/latest/userguide/session-manager-working-with-install-plugin.html)

### AWS Permissions

Your AWS user/role needs these permissions:
- EC2: RunInstances, TerminateInstances, DescribeInstances, CreateTags
- EC2: CreateSecurityGroup, DeleteSecurityGroup, AuthorizeSecurityGroupIngress
- SSM: StartSession, DescribeSessions
- EC2: CreateImage, DescribeImages (if using --create-ami)

## Quick Start

### Building Phase 1

```bash
# Run phase 1 build (launches instance and runs packer build)
aws-vault exec dev -- nix run .#pg-ami-builder -- build phase1 --postgres-version 15

# If packer build fails, instance stays alive for debugging
# SSH to investigate
aws-vault exec dev -- nix run .#pg-ami-builder -- ssh

# Make local changes and re-run with file sync
vim ansible/playbook.yml
aws-vault exec dev -- nix run .#pg-ami-builder -- ansible-rerun phase1 --sync-files

# Cleanup when done
aws-vault exec dev -- nix run .#pg-ami-builder -- cleanup
```

### Building Phase 2

```bash
# Run phase 2 with existing stage-1 AMI
aws-vault exec dev -- nix run .#pg-ami-builder -- build phase2 \
  --source-ami ami-stage1-xyz \
  --postgres-version 15
```

## Commands

### build phase1

Launch EC2 instance and run phase 1 ansible playbook.

```bash
nix run .#pg-ami-builder -- build phase1 --postgres-version 15 [flags]
```

**Flags:**
- `--postgres-version` (required) - PostgreSQL major version (15, 16, 17)
- `--region` - AWS region (default: us-east-1)
- `--create-ami` - Create AMI on success (default: false)
- `--ansible-args` - Additional ansible arguments
- `--instance-type` - EC2 instance type (default: c6g.4xlarge)
- `--state-file` - Custom state file path

### build phase2

Launch EC2 instance from stage-1 AMI and run phase 2 ansible playbook.

```bash
nix run .#pg-ami-builder -- build phase2 --source-ami ami-xyz --postgres-version 15 [flags]
```

**Flags:**
- `--source-ami` (required) - Stage-1 AMI ID
- `--postgres-version` (required) - PostgreSQL major version
- `--git-sha` - Git SHA for nix packages (default: current HEAD)
- Plus all flags from phase1

### ansible-rerun

Re-run ansible playbook on existing instance. Optionally sync local file changes first.

```bash
nix run .#pg-ami-builder -- ansible-rerun phase1 [flags]
```

**Flags:**
- `--instance-id` - Target specific instance (default: from state file)
- `--sync-files` - Sync local ansible/, scripts/, and migrations/ files before running (default: false)
- `--ansible-args` - Additional ansible arguments
- `--skip-tags` - Ansible tags to skip
- `--region` - AWS region (default: us-east-1)

**Examples:**

```bash
# Re-run without syncing files (use existing files on instance)
nix run .#pg-ami-builder -- ansible-rerun phase1

# Re-run with local file changes
nix run .#pg-ami-builder -- ansible-rerun phase1 --sync-files

# Re-run with skip tags
nix run .#pg-ami-builder -- ansible-rerun phase1 --skip-tags migrations
```

### ssh

Connect to instance via AWS SSM Session Manager (default) or EC2 Instance Connect.

```bash
nix run .#pg-ami-builder -- ssh [flags]
```

**Flags:**
- `--instance-id` - Target specific instance for SSM (default: from state file)
- `--region` - AWS region for SSM (default: us-east-1)
- `--aws-ec2-connect-cmd` - Full AWS EC2 Instance Connect command string

**Examples:**

```bash
# Connect via SSM (default)
nix run .#pg-ami-builder -- ssh

# Connect via EC2 Instance Connect
nix run .#pg-ami-builder -- ssh \
  --aws-ec2-connect-cmd "aws ec2-instance-connect ssh --instance-id i-024bba2db43e4b41f --region us-east-1"
```

### cleanup

Terminate instance and remove associated resources.

```bash
nix run .#pg-ami-builder -- cleanup [flags]
```

**Flags:**
- `--instance-id` - Target specific instance (default: from state file)
- `--force` - Skip confirmation prompt

## Workflows

### Workflow 1: Develop and test phase 1 changes

```bash
# Run phase 1 build (launches instance and runs packer build)
aws-vault exec dev -- nix run .#pg-ami-builder -- build phase1 --postgres-version 15

# If packer fails, instance stays up for debugging
# SSH to investigate
aws-vault exec dev -- nix run .#pg-ami-builder -- ssh

# Make local changes to ansible files
vim ansible/playbook.yml

# Re-run with your local changes
aws-vault exec dev -- nix run .#pg-ami-builder -- ansible-rerun phase1 --sync-files

# Repeat until working, then create AMI
aws-vault exec dev -- nix run .#pg-ami-builder -- build phase1 --postgres-version 15 --create-ami

# Cleanup
aws-vault exec dev -- nix run .#pg-ami-builder -- cleanup
```

### Workflow 2: Parallel builds for multiple postgres versions

```bash
# Build PG 15
aws-vault exec dev -- nix run .#pg-ami-builder -- build phase1 \
  --postgres-version 15 \
  --state-file ~/.pg-ami-build/pg15.json

# Build PG 16 in parallel
aws-vault exec dev -- nix run .#pg-ami-builder -- build phase1 \
  --postgres-version 16 \
  --state-file ~/.pg-ami-build/pg16.json

# SSH into PG 15 instance
aws-vault exec dev -- nix run .#pg-ami-builder -- ssh \
  --state-file ~/.pg-ami-build/pg15.json
```

## Troubleshooting

### SSM Connection Fails

1. Check SSM agent status on the instance
2. Verify instance profile has SSM permissions
3. Ensure session-manager-plugin is installed

### Ansible Fails

The instance is kept running on failure. Check logs:

```bash
# SSH into instance
nix run .#pg-ami-builder -- ssh

# Check ansible logs
sudo journalctl -u ansible-provisioner
```

### State File Issues

If state file references non-existent instance:

```bash
# Override with specific instance
nix run .#pg-ami-builder -- ssh --instance-id i-xxxxx

# Or clear state and start fresh
rm ~/.pg-ami-build/state.json
```

## Advanced Usage

### Custom State Files for Parallel Builds

Use `--state-file` to manage multiple builds:

```bash
nix run .#pg-ami-builder -- build phase1 \
  --postgres-version 15 \
  --state-file ~/.pg-ami-build/custom.json
```

### Additional Ansible Arguments

Pass custom arguments to ansible:

```bash
nix run .#pg-ami-builder -- build phase1 \
  --postgres-version 15 \
  --ansible-args="--skip-tags=migrations"
```

## State File

Location: `~/.pg-ami-build/state.json`

The state file tracks the current build instance, allowing subsequent commands to operate on the same instance without specifying `--instance-id`.

Example state:
```json
{
  "instance_id": "i-1234567890abcdef0",
  "phase": "phase1",
  "execution_id": "1731672000-15",
  "region": "us-east-1",
  "postgres_version": "15",
  "timestamp": "2025-11-15T10:30:00Z",
  "git_sha": "abc123def456"
}
```
