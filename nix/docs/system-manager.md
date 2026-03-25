# System manager

[system-manager](https://github.com/numtide/system-manager) provides declarative, Nix-based system configuration management for non-NixOS Linux systems.
It replaces imperative service setup with reproducible Nix module definitions, bringing NixOS-style service management to the AMI build without requiring a full NixOS installation.

## How it fits into the AMI build pipeline

The AMI build uses a two-stage pipeline orchestrated by Packer and Ansible.
Stage 1 installs Nix itself, while stage 2 uses Nix to build and deploy all services.
system-manager is deployed during stage 2 via the Ansible task `ansible/tasks/setup-system-manager.yml`.

### Installation

The `system-manager` binary is installed from the binary cache using the remote flake URL, pinned to the current git SHA:

```yaml
- name: Install system-manager from binary cache
  ansible.builtin.shell: |
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    nix profile add --accept-flake-config "github:supabase/postgres/{{ git_commit_sha }}#system-manager"
  become: true
```

### Activation

The system configuration is built from the remote flake URL (pulled from the binary cache), then registered and activated:

```yaml
- name: Build and activate system-manager config
  ansible.builtin.shell: |
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
    STORE_PATH=$(nix build --accept-flake-config --no-link --print-out-paths "github:supabase/postgres/{{ git_commit_sha }}#systemConfigs.$(nix eval --raw nixpkgs#system).default")
    system-manager register --store-path "$STORE_PATH" --sudo
    system-manager activate --store-path "$STORE_PATH" --sudo
  become: true
```

No source tree is uploaded to the build instance. Both the `system-manager` binary and the system configuration are fetched as pre-built artifacts from the `nix-postgres-artifacts` S3 binary cache.

## Updating system-manager on a running instance

system-manager can be updated on a running instance without rebuilding the AMI. To apply a new configuration:

```bash
# Build the new config (fetched from binary cache)
STORE_PATH=$(nix build --accept-flake-config --no-link --print-out-paths \
  "github:supabase/postgres/<new-sha>#systemConfigs.$(uname -m)-linux.default")

# Register and activate
system-manager register --store-path "$STORE_PATH" --sudo
system-manager activate --store-path "$STORE_PATH" --sudo
```

This pulls the pre-built configuration from the binary cache and activates it. system-manager diffs the old and new state and reconciles — starting, stopping, or restarting services and updating `/etc` entries as needed. No explicit deactivation is required.

To also update the `system-manager` binary itself (if the upstream version changed in `flake.lock`):

```bash
nix profile upgrade --accept-flake-config system-manager
```

Changes applied this way include anything modified in `nix/systemModules/` between the old and new SHA: new or removed systemd services, `environment.etc` entries, packages under `/run/system-manager/sw/`, etc.

## Nix configuration walkthrough

### Flake input

The system-manager flake input is declared in `flake.nix`, pinned to the upstream repository with nixpkgs following the main input:

```nix
system-manager.inputs.nixpkgs.follows = "nixpkgs";
system-manager.url = "github:numtide/system-manager";
```

The `system-manager` binary is also re-exported as a package in `nix/packages/default.nix` (Linux only), making it available as `nix profile add .#system-manager` or via the remote flake URL.

The flake outputs import both the module registry and the system configurations:

```nix
imports = [
  # ...
  nix/systemModules
  nix/systemConfigs.nix
];
```

### System configurations

`nix/systemConfigs.nix` defines the top-level system configurations for each supported architecture.
It calls `system-manager.lib.makeSystemConfig` to produce a configuration from the enabled modules:

```nix
mkSystemConfig = system: {
  name = system;
  value.default = inputs.system-manager.lib.makeSystemConfig {
    modules = mkModules system;
    extraSpecialArgs = {
      inherit self;
      inherit system;
    };
  };
};
```

The `mkModules` function returns the list of modules to enable.
Currently it includes the genesis placeholder module and sets the host platform:

```nix
mkModules = system: [
  self.systemModules.genesis
  ({
    nixpkgs.hostPlatform = system;
  })
];
```

Configurations are built for both `aarch64-linux` and `x86_64-linux`.

### System modules

`nix/systemModules/default.nix` is the module registry.
It is a flake-parts module that exports individual system modules under `flake.systemModules`:

```nix
{
  imports = [ ./tests ];
  flake = {
    systemModules = {
      genesis = {
        #this file is just a placeholder to bootstrap
        #the system manager, it will be replaced by real configurations
        environment.etc."system-manager-genesis" = {
          text = "";
          user = "root";
          group = "root";
          mode = "0644";
        };
      };
    };
  };
}
```

## Adding a new system module

To add a new system module:

1. Create a new `.nix` file under `nix/systemModules/`, for example `nix/systemModules/my-service.nix`.
   The module is a standard NixOS-style module with options and config:

    ```nix
    {
      lib,
      config,
      ...
    }:
    let
      cfg = config.supabase.services.my-service;
    in
    {
      options = {
        supabase.services.my-service = {
          enable = lib.mkEnableOption "Whether to enable the my-service systemd service.";
        };
      };

      config = lib.mkIf cfg.enable {
        # systemd units, environment.etc entries, etc.
      };
    }
    ```

2. Register the module in `nix/systemModules/default.nix` by adding it to the `systemModules` attribute set:

    ```nix
    systemModules = {
      my-service = ./my-service.nix;
    };
    ```

3. Include and enable the module in `nix/systemConfigs.nix` by adding it to the `mkModules` list and setting the enable option:

    ```nix
    mkModules = system: [
      self.systemModules.my-service
      ({
        supabase.services.my-service.enable = true;
        nixpkgs.hostPlatform = system;
      })
    ];
    ```

4. Add a test assertion to the test script in `nix/systemModules/tests/default.nix` (see below).

## Testing

### Container tests

Tests are defined in `nix/systemModules/tests/default.nix` using `system-manager.lib.containerTest.makeContainerTest`.
This creates a lightweight container-based NixOS test that validates the system configuration:

```nix
check-system-manager =
  let
    toplevel = self.systemConfigs.${pkgs.system}.default;
  in
  inputs.system-manager.lib.containerTest.makeContainerTest {
    hostPkgs = pkgs;
    name = "check-system-manager";
    inherit toplevel;
    testScript = ''
      start_all()

      machine.wait_for_unit("multi-user.target")

      machine.activate()
      machine.wait_for_unit("system-manager.target")

      with subtest("Verify genesis file"):
          assert machine.file("/etc/system-manager-genesis").exists, "/etc/system-manager-genesis should exist"
          assert machine.file("/etc/system-manager-genesis").mode == 0o644, "/etc/system-manager-genesis should have mode 0644"
          assert machine.file("/etc/system-manager-genesis").user == "root", "/etc/system-manager-genesis should be owned by root"
          assert machine.file("/etc/system-manager-genesis").group == "root", "/etc/system-manager-genesis should be owned by root"
    '';
  };
```

The test script starts the container, waits for systemd to reach `multi-user.target`, activates the system-manager configuration, then verifies that managed services and files are present.
When adding a new module, extend the `testScript` with an additional `subtest` block that asserts the new service is running.

### Running tests locally

The container tests use `systemd-nspawn` which requires the `uid-range` nix feature. This in turn requires `auto-allocate-uids` and the `auto-allocate-uids` experimental feature to be enabled on the Linux machine running the tests.

**On macOS:** These tests cannot run natively on macOS. You need to enter the shell of a Linux VM (e.g. an Ubuntu VM via OrbStack, UTM, or similar) and run the tests from there.

Ensure your Linux machine's `/etc/nix/nix.conf` includes:

```
auto-allocate-uids = true
extra-experimental-features = nix-command flakes auto-allocate-uids cgroups
trusted-users = root @wheel @sudo
```

After updating the config, restart the nix daemon:

```bash
sudo systemctl restart nix-daemon
```

Then run the system-manager check:

```bash
nix build .#checks.aarch64-linux.check-system-manager -L
```

Or for x86_64:

```bash
nix build .#checks.x86_64-linux.check-system-manager -L
```

The `-L` flag streams build logs for visibility.
These checks only run on Linux (gated by `lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux`).

## CI integration

The `check-system-manager` derivation is part of the flake's `checks` output, so it runs automatically in the `nix-build-checks-*` jobs of the main `nix-build.yml` workflow alongside all other checks.

## Runtime effects

After `system-manager activate` runs, managed software is available under `/run/system-manager/sw/`.
This affects paths throughout the system.
For example, the audit baseline `audit-specs/baselines/ami-build/user.yml` references these paths for user shells:

```yaml
root:
  exists: true
  home: /root
  shell: /run/system-manager/sw/bin/bash
nobody:
  exists: true
  shell: /run/system-manager/sw/bin/nologin
```

When adding new services or modifying system-manager configuration, update the audit baselines accordingly to reflect any changes to user shells, service users, or file paths that `supascan` validates during AMI builds.
