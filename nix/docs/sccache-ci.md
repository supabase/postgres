# sccache in CI

This document explains how sccache is integrated into the Nix CI pipeline to accelerate Rust compilation for pgrx-based PostgreSQL extensions.

## Overview

Building pgrx extensions (pg_graphql, pg_jsonschema, wrappers, etc.) involves significant Rust compilation.
sccache caches compiled artifacts to speed up subsequent builds when source code hasn't changed.

The integration required solving several challenges around Nix's sandboxed builds and CI runner persistence.

## Architecture

Ephemeral CI runners (Blacksmith) use stickydisk for persistent storage at `/nix/var/cache/sccache`.
Self-hosted Darwin runners use a local directory at the same path.

The cache is keyed by PostgreSQL version to avoid cross-version cache pollution:
- Extension packages: `sccache-Linux-ARM64-pg17`, `sccache-Linux-ARM64-pg15`, etc.
- Non-extension packages: `sccache-Linux-ARM64-shared`

| Platform | Runner type | sccache enabled |
|----------|-------------|-----------------|
| x86_64-linux | Blacksmith ephemeral | Yes (extensions only) |
| aarch64-linux | Blacksmith ephemeral | Yes (extensions only) |
| aarch64-linux | Self-hosted (KVM packages) | No |
| aarch64-darwin | Self-hosted | Yes (extensions only) |

## Nix sandbox integration

Nix builds run in a sandbox that isolates the build environment.
To allow sccache to persist across builds, the cache directory must be mounted into the sandbox via `extra-sandbox-paths`.

### Linux with auto-allocate-uids

On Linux, we use Nix's `auto-allocate-uids` feature which creates user namespaces for builds.
This introduces a UID mapping challenge.

The base UID is 872415232 (0x34000000).
Inside the sandbox, processes run as root (UID 0), but outside the sandbox this maps to UID 872415232.
Files created inside the sandbox are owned by this mapped UID.

The workflow changes ownership to UID 872415232 before builds to ensure cache access works correctly.

### Darwin

Darwin doesn't have user namespaces.
Builds run as nixbld users (members of the `nixbld` group).
The cache directory is owned by the nixbld group with setgid permissions.

## Compromises and limitations

### max-jobs = 1 for extensions

With `auto-allocate-uids`, each parallel Nix build gets a different UID slot (872415232, 872480768, etc.).
When multiple builds run in parallel, they create files with different ownership, causing EPERM errors when one build tries to update another's cache files.

To avoid this, extension builds use `max-jobs = 1`, serializing Nix builds so all use the same UID slot.
Non-extension packages don't use sccache and can build in parallel.

### Blacksmith stickydisk last-writer-wins

Blacksmith's stickydisk has "last writer wins" semantics for concurrent writes.
If multiple jobs write to the same cache key simultaneously, only the last job's writes persist.

We mitigate this by using per-PostgreSQL-version cache keys, reducing concurrent writes to the same cache.

### Extensions only

sccache is only enabled for extension packages (those with `postgresql_version` in the matrix).
Non-extension packages (PostgreSQL itself, tooling) build without sccache to allow parallel builds.

## Debugging

To check sccache statistics, look for output at the end of extension builds:

```
sccache stats:
Compile requests                    150
Compile requests executed           148
Cache hits                          120
Cache misses                         28
```

## References

- [Nix auto-allocate-uids](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-auto-allocate-uids)
- [sccache](https://github.com/mozilla/sccache)
- [Blacksmith stickydisk](https://blacksmith.sh/docs/stickydisk)
