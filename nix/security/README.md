# Security Layer: Tetragon + osquery

Runtime security monitoring for Supabase PostgreSQL instances, deployed via [numtide/system-manager](https://github.com/numtide/system-manager).

## Overview

This module provides two system-manager profiles:

- **security-full**: Tetragon (runtime process enforcement) + osquery (compliance inventory). For instances with >= 1GB RAM.
- **security-lite**: osquery only. For all instances including Nano (0.5GB).

system-manager manages these tools as an isolated Nix layer alongside the existing apt-managed system. It does not modify or conflict with any existing packages, services, or configurations.

## What system-manager manages

| Component | Managed paths |
|-----------|--------------|
| Tetragon | `/etc/tetragon/`, `tetragon.service` |
| osquery | `/etc/osquery/`, `osqueryd.service` |
| Binaries | `/nix/store/*` (symlinked to `/run/system-manager/sw/bin/`) |

**Not touched:** PostgreSQL, pgbouncer, PostgREST, fail2ban, cron, or any other apt/nix-managed package or service.

## Applying the configuration

### Automated (via Ansible)

The Ansible playbook automatically selects the profile based on `/etc/supabase/instance-memory-mb`:

```bash
# During AMI build or instance provisioning
ansible-playbook playbook.yml
```

### Manual

```bash
# Full profile (tetragon + osquery)
nix run 'github:numtide/system-manager' -- switch --sudo \
  --flake '.#security-full'

# Lite profile (osquery only)
nix run 'github:numtide/system-manager' -- switch --sudo \
  --flake '.#security-lite'
```

## Verifying services

```bash
# Check service status
systemctl status tetragon
systemctl status osqueryd

# Verify system-manager target
systemctl status system-manager.target
```

## Checking Tetragon events

```bash
# Tail live events
tail -f /var/log/tetragon/events.log | jq .

# Search for specific event types
cat /var/log/tetragon/events.log | jq 'select(.process_exec != null)'

# Check loaded policies
tetra tracingpolicy list
```

## Switching profiles

To switch from lite to full (or vice versa):

```bash
# Switch to full profile
nix run 'github:numtide/system-manager' -- switch --sudo \
  --flake '.#security-full'

# Switch back to lite profile
nix run 'github:numtide/system-manager' -- switch --sudo \
  --flake '.#security-lite'
```

system-manager handles the transition cleanly — it stops removed services and starts new ones.

## Deactivating

To remove all system-manager managed services and configs:

```bash
nix run 'github:numtide/system-manager' -- deactivate --sudo
```

This cleanly removes Tetragon, osquery, their configs, and any symlinks. No apt packages are affected.

## TracingPolicies

Four Tetragon TracingPolicies are installed in `/etc/tetragon/tetragon.tp.d/`:

| Policy | What it monitors |
|--------|-----------------|
| `unexpected-exec.yaml` | Process executions outside the allowlist |
| `sensitive-writes.yaml` | Writes to `/etc/passwd`, `/etc/shadow`, `/etc/ssh`, `/root/.ssh`, PostgreSQL configs |
| `network-monitor.yaml` | Outbound connections from non-allowlisted processes |
| `privilege-escalation.yaml` | `commit_creds` and `setuid` calls |

All policies run in **detection mode** (`action: Post`). To enable enforcement, change `action: Post` to `action: Sigkill` in the policy YAML files.

## Resource limits

| Service | Memory limit | CPU limit |
|---------|-------------|-----------|
| Tetragon | 100MB (`MemoryMax`) | 5% (`CPUQuota`) |
| osquery | 50MB (watchdog) | 5% (watchdog) |

## Known considerations

- Tetragon requires kernel eBPF support (available on Ubuntu 24.04 with kernel 6.x).
- The `unexpected-exec.yaml` allowlist includes `/nix/store` since system-manager binaries run from there.
- osquery's `unexpected_processes` query also excludes `/nix/store%` paths.
- system-manager creates its services under `system-manager.target`, which is a dependency of `default.target`. This means system-manager services start at boot but are isolated from `multi-user.target` services.
