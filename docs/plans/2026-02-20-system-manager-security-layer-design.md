# System-Manager Security Layer: Tetragon + osquery

## Overview

Deploy Tetragon (runtime process enforcement) and osquery (compliance inventory) on Supabase PostgreSQL EC2 instances using numtide/system-manager. system-manager provides NixOS-style declarative configuration on Ubuntu 24.04 without conflicting with existing apt-managed packages.

## Architecture

### File Structure

```
nix/security/
├── default.nix              # flake-parts module exposing systemConfigs
├── tetragon.nix             # tetragon service + config module
├── osquery.nix              # osquery service + config module
├── policies/
│   ├── unexpected-exec.yaml
│   ├── sensitive-writes.yaml
│   ├── network-monitor.yaml
│   └── privilege-escalation.yaml
```

Changes to existing files:
- `flake.nix` — add `system-manager` input, import `nix/security`
- `ansible/tasks/` — new task file for system-manager activation

### Two Profiles

- **`security-full`**: osquery + tetragon (instances >= 1GB RAM)
- **`security-lite`**: osquery only (nano/micro instances < 1GB)

Both built via `system-manager.lib.makeSystemConfig`. Ansible reads `/etc/supabase/instance-memory-mb` at deploy time to select the profile.

## Components

### Tetragon (`tetragon.nix`)

- Package: `pkgs.tetragon` from nixpkgs
- systemd service with `MemoryMax=100M`, `CPUQuota=5%`, `wantedBy = ["system-manager.target"]`
- Config at `/etc/tetragon/tetragon.yaml`: JSON export to `/var/log/tetragon/events.log`, `export-rate-limit: 100`
- TracingPolicy YAMLs in `/etc/tetragon/tetragon.tp.d/` via `environment.etc`
- Log directory `/var/log/tetragon` created via `systemd.tmpfiles.rules`

### TracingPolicies

1. **unexpected-exec.yaml**: `sys_execve` hook, allowlist: `/usr/lib/postgresql`, `/usr/bin/pg_*`, `/opt/supabase`, `/usr/sbin/cron`, `/usr/bin/pgbouncer`, `/usr/bin/postgrest`, `/nix/store`. Detection mode (`action: Post`), comment for enforcement (`action: Sigkill`).
2. **sensitive-writes.yaml**: `sys_openat` with `O_WRONLY`/`O_RDWR`, monitors `/etc/passwd`, `/etc/shadow`, `/etc/ssh/`, `/root/.ssh/`, PostgreSQL config paths.
3. **network-monitor.yaml**: `sys_connect`, alerts on outbound from non-allowlisted processes to non-allowlisted ports (not 5432/6543/443/53/80).
4. **privilege-escalation.yaml**: `commit_creds` and `sys_setuid` hooks.

### osquery (`osquery.nix`)

- Package: `pkgs.osquery` from nixpkgs
- systemd service `wantedBy = ["system-manager.target"]`
- Config at `/etc/osquery/osquery.conf` with watchdog limits (50MB memory, 5% CPU)
- Scheduled queries: listening_ports (300s), unexpected_processes (120s), authorized_keys (3600s), crontab (600s), kernel_modules (3600s), system_info (3600s)

## Coexistence

system-manager only manages what it explicitly declares. It does not touch:
- apt-managed packages or services (postgresql, pgbouncer, fail2ban, etc.)
- Existing `/etc` paths not declared in the config
- Existing nix profile packages

| Managed by system-manager | NOT touched |
|---|---|
| `/etc/tetragon/*` | `/etc/postgresql/*` |
| `/etc/osquery/*` | `/etc/pgbouncer/*` |
| `tetragon.service` | `postgresql.service` |
| `osqueryd.service` | `pgbouncer.service` |

## Ansible Integration

New task `ansible/tasks/setup-security-layer.yml` reads `/etc/supabase/instance-memory-mb` and runs `system-manager switch` with the appropriate profile. Added to the main playbook after existing setup tasks.

## Deployment

```bash
# Apply full profile (tetragon + osquery)
nix run github:numtide/system-manager -- switch --sudo --flake '.#security-full'

# Apply lite profile (osquery only)
nix run github:numtide/system-manager -- switch --sudo --flake '.#security-lite'

# Deactivate (cleanly removes everything)
nix run github:numtide/system-manager -- deactivate --sudo
```
