# System-Manager Security Layer Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Deploy Tetragon and osquery on Supabase PostgreSQL EC2 instances via numtide/system-manager, managed by Ansible.

**Architecture:** Two system-manager profiles (`security-full` with tetragon+osquery, `security-lite` with osquery-only) exposed as `systemConfigs` from the existing flake. system-manager manages only `/etc/tetragon/`, `/etc/osquery/`, and two systemd services — everything else is untouched. Ansible selects the profile based on instance RAM at deploy time.

**Tech Stack:** Nix (flake-parts), numtide/system-manager, tetragon (nixpkgs), osquery (nixpkgs), Ansible

---

### Task 1: Add system-manager input to flake.nix

**Files:**
- Modify: `flake.nix`

**Step 1: Add the system-manager flake input**

In `flake.nix`, add `system-manager` to the `inputs` block:

```nix
system-manager.url = "github:numtide/system-manager";
system-manager.inputs.nixpkgs.follows = "nixpkgs";
```

**Step 2: Add the security module import**

In the `imports` list inside the `outputs` function, add:

```nix
nix/security
```

**Step 3: Update flake.lock**

Run: `nix flake update system-manager`

**Step 4: Commit**

```bash
git add flake.nix flake.lock
git commit -m "feat: add system-manager input for security layer"
```

---

### Task 2: Create osquery module

**Files:**
- Create: `nix/security/osquery.nix`

**Step 1: Write the osquery module**

```nix
{ pkgs, ... }:
{
  environment.systemPackages = [ pkgs.osquery ];

  environment.etc."osquery/osquery.conf" = {
    text = builtins.toJSON {
      options = {
        config_plugin = "filesystem";
        logger_plugin = "filesystem";
        logger_path = "/var/log/osquery";
        disable_logging = false;
        schedule_splay_percent = 10;
        pidfile = "/var/run/osquery/osqueryd.pidfile";
        events_expiry = 3600;
        database_path = "/var/osquery/osquery.db";
        verbose = false;
        worker_threads = 2;
        watchdog_memory_limit = 50;
        watchdog_utilization_limit = 5;
      };
      schedule = {
        listening_ports = {
          query = "SELECT pid, port, protocol, address, name FROM listening_ports WHERE port NOT IN (5432, 6543, 8000, 3000);";
          interval = 300;
          description = "Listening ports excluding known Supabase services";
        };
        unexpected_processes = {
          query = "SELECT pid, name, path, cmdline, uid FROM processes WHERE uid = 0 AND path NOT LIKE '/usr/lib/postgresql%' AND path NOT LIKE '/opt/supabase%' AND path NOT LIKE '/usr/sbin/%' AND path NOT LIKE '/nix/store%';";
          interval = 120;
          description = "Root processes with unexpected binary paths";
        };
        authorized_keys = {
          query = "SELECT * FROM authorized_keys;";
          interval = 3600;
          description = "SSH authorized keys inventory";
        };
        crontab = {
          query = "SELECT * FROM crontab;";
          interval = 600;
          description = "Scheduled cron jobs";
        };
        kernel_modules = {
          query = "SELECT name, size, status, address FROM kernel_modules;";
          interval = 3600;
          description = "Loaded kernel modules";
        };
        system_info = {
          query = "SELECT hostname, cpu_brand, physical_memory, hardware_vendor, hardware_model FROM system_info;";
          interval = 3600;
          description = "System hardware and OS information";
        };
      };
    };
    mode = "0644";
  };

  systemd.services.osqueryd = {
    enable = true;
    description = "osquery daemon";
    after = [ "network.target" "syslog.target" ];
    wantedBy = [ "system-manager.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStartPre = "${pkgs.coreutils}/bin/mkdir -p /var/log/osquery /var/osquery /var/run/osquery";
      ExecStart = "${pkgs.osquery}/bin/osqueryd --config_path /etc/osquery/osquery.conf --pidfile /var/run/osquery/osqueryd.pidfile --database_path /var/osquery/osquery.db";
      Restart = "on-failure";
      RestartSec = 10;
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/log/osquery 0755 root root -"
    "d /var/osquery 0755 root root -"
    "d /var/run/osquery 0755 root root -"
  ];
}
```

**Step 2: Commit**

```bash
git add nix/security/osquery.nix
git commit -m "feat: add osquery system-manager module"
```

---

### Task 3: Create Tetragon TracingPolicy YAML files

**Files:**
- Create: `nix/security/policies/unexpected-exec.yaml`
- Create: `nix/security/policies/sensitive-writes.yaml`
- Create: `nix/security/policies/network-monitor.yaml`
- Create: `nix/security/policies/privilege-escalation.yaml`

**Step 1: Write unexpected-exec.yaml**

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: "unexpected-exec"
spec:
  kprobes:
  - call: "sys_execve"
    syscall: true
    args:
    - index: 0
      type: "string"
    selectors:
    - matchBinaries:
      - operator: "NotPrefix"
        values:
        - "/usr/lib/postgresql"
        - "/usr/bin/pg_"
        - "/opt/supabase"
        - "/usr/sbin/cron"
        - "/usr/bin/pgbouncer"
        - "/usr/bin/postgrest"
        - "/nix/store"
      matchActions:
      # Detection mode: log unexpected executions
      # Change to "action: Sigkill" for enforcement mode
      - action: Post
```

**Step 2: Write sensitive-writes.yaml**

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: "sensitive-writes"
spec:
  kprobes:
  - call: "sys_openat"
    syscall: true
    args:
    - index: 0
      type: "int"
    - index: 1
      type: "string"
    - index: 2
      type: "int"
    selectors:
    - matchArgs:
      - index: 1
        operator: "Prefix"
        values:
        - "/etc/passwd"
        - "/etc/shadow"
        - "/etc/ssh"
        - "/root/.ssh"
      - index: 2
        operator: "Mask"
        values:
        - "1"    # O_WRONLY
        - "2"    # O_RDWR
      matchActions:
      - action: Post
    - matchArgs:
      - index: 1
        operator: "Prefix"
        values:
        - "/etc/postgresql"
        - "/var/lib/postgresql"
      - index: 2
        operator: "Mask"
        values:
        - "1"    # O_WRONLY
        - "2"    # O_RDWR
      matchActions:
      - action: Post
```

**Step 3: Write network-monitor.yaml**

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: "network-monitor"
spec:
  kprobes:
  - call: "sys_connect"
    syscall: true
    args:
    - index: 0
      type: "int"
    - index: 1
      type: "sockaddr"
    selectors:
    - matchBinaries:
      - operator: "NotIn"
        values:
        - "/usr/lib/postgresql/bin/postgres"
        - "/usr/bin/pgbouncer"
        - "/usr/bin/postgrest"
      matchActions:
      - action: Post
```

Note: This hooks `sys_connect` for processes other than postgres/pgbouncer/postgrest. Port-level filtering (5432, 6543, 443, 53, 80) would require matching on the sockaddr arg which has BPF constraints. The policy captures all outbound connect() from unexpected processes; port filtering can be done in the log pipeline.

**Step 4: Write privilege-escalation.yaml**

```yaml
apiVersion: cilium.io/v1alpha1
kind: TracingPolicy
metadata:
  name: "privilege-escalation"
spec:
  kprobes:
  - call: "commit_creds"
    syscall: false
    args:
    - index: 0
      type: "cred"
    selectors:
    - matchActions:
      - action: Post
  - call: "sys_setuid"
    syscall: true
    args:
    - index: 0
      type: "int"
    selectors:
    - matchActions:
      - action: Post
```

**Step 5: Commit**

```bash
git add nix/security/policies/
git commit -m "feat: add Tetragon TracingPolicy YAML files"
```

---

### Task 4: Create Tetragon module

**Files:**
- Create: `nix/security/tetragon.nix`

**Step 1: Write the tetragon module**

```nix
{ pkgs, ... }:
let
  policyDir = ./policies;
in
{
  environment.systemPackages = [ pkgs.tetragon ];

  environment.etc."tetragon/tetragon.yaml" = {
    text = builtins.toJSON {
      export-filename = "/var/log/tetragon/events.log";
      export-rate-limit = 100;
      export-file-max-size-mb = 10;
      export-file-max-backups = 5;
      tracing-policy-dir = "/etc/tetragon/tetragon.tp.d";
    };
    mode = "0644";
  };

  environment.etc."tetragon/tetragon.tp.d/unexpected-exec.yaml" = {
    source = "${policyDir}/unexpected-exec.yaml";
    mode = "0644";
  };

  environment.etc."tetragon/tetragon.tp.d/sensitive-writes.yaml" = {
    source = "${policyDir}/sensitive-writes.yaml";
    mode = "0644";
  };

  environment.etc."tetragon/tetragon.tp.d/network-monitor.yaml" = {
    source = "${policyDir}/network-monitor.yaml";
    mode = "0644";
  };

  environment.etc."tetragon/tetragon.tp.d/privilege-escalation.yaml" = {
    source = "${policyDir}/privilege-escalation.yaml";
    mode = "0644";
  };

  systemd.services.tetragon = {
    enable = true;
    description = "Tetragon eBPF security observability";
    after = [ "network.target" ];
    wantedBy = [ "system-manager.target" ];
    serviceConfig = {
      Type = "simple";
      ExecStart = "${pkgs.tetragon}/bin/tetragon --config-file /etc/tetragon/tetragon.yaml";
      Restart = "on-failure";
      RestartSec = 10;
      MemoryMax = "100M";
      CPUQuota = "5%";
      # Tetragon needs these capabilities for eBPF
      AmbientCapabilities = "CAP_SYS_ADMIN CAP_BPF CAP_PERFMON";
      CapabilityBoundingSet = "CAP_SYS_ADMIN CAP_BPF CAP_PERFMON";
    };
  };

  systemd.tmpfiles.rules = [
    "d /var/log/tetragon 0755 root root -"
  ];
}
```

**Step 2: Commit**

```bash
git add nix/security/tetragon.nix
git commit -m "feat: add Tetragon system-manager module"
```

---

### Task 5: Create the flake-parts security module (default.nix)

**Files:**
- Create: `nix/security/default.nix`

This is the flake-parts module that wires everything together and exposes the two system-manager profiles.

**Step 1: Write default.nix**

```nix
# nix/security/default.nix
#
# Flake-parts module that exposes system-manager configurations
# for security tooling (Tetragon + osquery).
#
# Two profiles:
#   - security-full: osquery + tetragon (instances >= 1GB RAM)
#   - security-lite: osquery only (all instances)
{ inputs, ... }:
{
  flake = {
    systemConfigs = {
      security-full = inputs.system-manager.lib.makeSystemConfig {
        modules = [
          ./osquery.nix
          ./tetragon.nix
          {
            nixpkgs.hostPlatform = "aarch64-linux";
            system-manager.allowAnyDistro = true;
          }
        ];
      };

      security-lite = inputs.system-manager.lib.makeSystemConfig {
        modules = [
          ./osquery.nix
          {
            nixpkgs.hostPlatform = "aarch64-linux";
            system-manager.allowAnyDistro = true;
          }
        ];
      };
    };
  };
}
```

Note: `system-manager.allowAnyDistro = true` is set because our Ubuntu 24.04 AMI may not match the exact distro check. The `hostPlatform` is `aarch64-linux` matching the EC2 ARM instances; if x86_64 instances are also used, we may need per-arch configs.

**Step 2: Commit**

```bash
git add nix/security/default.nix
git commit -m "feat: add flake-parts security module with system-manager profiles"
```

---

### Task 6: Create Ansible task for system-manager activation

**Files:**
- Create: `ansible/tasks/setup-security-layer.yml`
- Modify: `ansible/playbook.yml`

**Step 1: Write the Ansible task file**

```yaml
# ansible/tasks/setup-security-layer.yml
# Applies system-manager security profile based on instance memory size.
# Instances >= 1024MB get tetragon + osquery (security-full).
# Smaller instances get osquery only (security-lite).

- name: Read instance memory size
  shell: cat /etc/supabase/instance-memory-mb 2>/dev/null || echo "0"
  register: instance_memory_raw
  changed_when: false

- name: Set security profile based on instance memory
  set_fact:
    security_profile: "{{ 'security-full' if (instance_memory_raw.stdout | int) >= 1024 else 'security-lite' }}"

- name: Display selected security profile
  debug:
    msg: "Instance memory: {{ instance_memory_raw.stdout }}MB -> profile: {{ security_profile }}"

- name: Apply system-manager security profile
  become: yes
  shell: |
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    nix run 'github:numtide/system-manager' -- switch --sudo --flake '/tmp/ansible-playbook#{{ security_profile }}'
  environment:
    NIX_CONFIG: "experimental-features = nix-command flakes"
```

**Step 2: Add task to playbook.yml**

Add the following block in `ansible/playbook.yml` after the "Install security tools" task (after line 173) and before "Clean out build dependencies":

```yaml
    - name: Apply system-manager security layer
      import_tasks: tasks/setup-security-layer.yml
      when: stage2_nix
```

**Step 3: Commit**

```bash
git add ansible/tasks/setup-security-layer.yml ansible/playbook.yml
git commit -m "feat: add Ansible task for system-manager security layer activation"
```

---

### Task 7: Create README for the security layer

**Files:**
- Create: `nix/security/README.md`

**Step 1: Write the README**

Document:
- Overview of what system-manager manages
- How to apply the configuration manually (`nix run github:numtide/system-manager -- switch --sudo --flake '.#security-full'`)
- How to verify services (`systemctl status tetragon osqueryd`)
- How to check Tetragon events (`cat /var/log/tetragon/events.log | jq .`)
- How to switch between profiles
- How to deactivate (`nix run github:numtide/system-manager -- deactivate --sudo`)
- Coexistence notes: what system-manager manages vs what apt/existing-nix manages
- Known constraints: tetragon requires kernel eBPF support, MemoryMax/CPUQuota limits

**Step 2: Commit**

```bash
git add nix/security/README.md
git commit -m "docs: add security layer README"
```

---

### Task 8: Validate the Nix build

**Step 1: Run nix flake check**

Run: `nix flake check --no-build`
Expected: No evaluation errors

**Step 2: Build the security-full profile**

Run: `nix build .#systemConfigs.security-full --dry-run`
Expected: Shows the build plan without errors

**Step 3: Build the security-lite profile**

Run: `nix build .#systemConfigs.security-lite --dry-run`
Expected: Shows the build plan without errors

**Step 4: Commit any fixes if needed**
