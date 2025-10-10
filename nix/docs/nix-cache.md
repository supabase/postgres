# Nix Cache Documentation

This document explains the Nix binary cache system used in the Supabase PostgreSQL project to speed up builds and share pre-built artifacts.

## What is the Nix Cache?

The Nix cache is a binary cache that stores pre-built Nix packages, allowing developers to download pre-compiled artifacts instead of building them from source. This significantly speeds up development and CI builds.

## Cache Configuration

The project uses a custom Nix binary cache hosted on AWS S3:

- **Cache URL**: `https://nix-postgres-artifacts.s3.amazonaws.com`
- **Primary Cache**: `https://cache.nixos.org` (upstream Nix cache)
- **Trusted Public Key**: `nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=%`

## How It Works

### 1. Cache Substituters

The cache is configured with two substituters:

```bash
substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com
```

This means Nix will:
1. First check the upstream Nix cache (`cache.nixos.org`)
2. Then check the Supabase-specific cache (`nix-postgres-artifacts.s3.amazonaws.com`)

### 2. Trusted Public Keys

```bash
trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

These keys ensure that only trusted, signed artifacts are downloaded from the caches.

### 3. Post-Build Hook

The cache includes a post-build hook that automatically uploads newly built packages to the cache:

```bash
post-build-hook = /etc/nix/upload-to-cache.sh
```

## Where Cache is Configured

The cache configuration is duplicated across multiple files in the project:

### CI/CD Workflows
- `.github/workflows/nix-build.yml` - Main build workflow
- `.github/workflows/ami-release-nix.yml` - AMI release workflow

### Docker Images
- `docker/nix/Dockerfile` - Nix Docker image
- `Dockerfile-15`, `Dockerfile-17`, `Dockerfile-orioledb-17` - PostgreSQL Docker images

### Provisioning Scripts
- `scripts/nix-provision.sh` - Local provisioning
- `ebssurrogate/scripts/qemu-bootstrap-nix.sh` - QEMU bootstrap
- `ansible/files/admin_api_scripts/pg_upgrade_scripts/initiate.sh` - Upgrade scripts

## Using the Cache Locally

### Automatic Configuration

The cache is automatically configured when you:

1. **Enter the development shell**:
   ```bash
   nix develop
   ```

2. **Run CI workflows** - Cache is configured automatically

3. **Use Docker images** - Cache is pre-configured

### Manual Configuration

If you need to configure the cache manually, add these lines to your `~/.config/nix/nix.conf`:

```bash
substituters = https://cache.nixos.org https://nix-postgres-artifacts.s3.amazonaws.com
trusted-public-keys = nix-postgres-artifacts:dGZlQOvKcNEjvT7QEAJbcV6b6uk7VF/hWMjhYleiaLI=% cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=
```

### Verifying Cache Usage

You can verify that the cache is working by checking the build logs:

```bash
# Look for cache hits in build output
nix build .#psql_15/bin --verbose

# Check cache status
nix show-config | grep substituters
```

## Cache Benefits

### For Developers
- **Faster builds** - Pre-built packages download instead of compiling
- **Consistent environments** - Same artifacts across different machines
- **Reduced bandwidth** - Only download what's needed

### For CI/CD
- **Faster CI runs** - Builds complete in minutes instead of hours
- **Reduced resource usage** - Less CPU and memory consumption
- **Better reliability** - Fewer build failures due to compilation issues

## Troubleshooting

### Cache Not Working

If you're not getting cache hits:

1. **Check configuration**:
   ```bash
   nix show-config | grep substituters
   ```

2. **Verify network access**:
   ```bash
   curl -I https://nix-postgres-artifacts.s3.amazonaws.com
   ```

3. **Check trusted keys**:
   ```bash
   nix show-config | grep trusted-public-keys
   ```

### Cache Misses

If you're seeing cache misses for packages that should be cached:

1. **Check if the package was recently built** - New packages may not be cached yet
2. **Verify the package hash** - Different inputs produce different hashes
3. **Check CI logs** - Ensure the post-build hook is working

### Network Issues

If you're having network issues with the cache:

1. **Try the upstream cache only**:
   ```bash
   nix build .#psql_15/bin --substituters https://cache.nixos.org
   ```

2. **Disable cache temporarily**:
   ```bash
   nix build .#psql_15/bin --no-substituters
   ```

## Cache Management

### Uploading to Cache

The cache is automatically populated by:

1. **CI builds** - GitHub Actions upload successful builds
2. **Post-build hooks** - Automatic upload after local builds
3. **Manual uploads** - Using `nix copy` command

### Cache Contents

The cache contains:
- **PostgreSQL binaries** (15, 17, orioledb-17)
- **Extension packages** (all 50+ extensions)
- **Development tools** (build tools, test frameworks)
- **Dependencies** (libraries, compilers, etc.)

## Security

The cache uses cryptographic signatures to ensure:
- **Integrity** - Packages haven't been tampered with
- **Authenticity** - Packages come from trusted sources
- **Reproducibility** - Same inputs produce same outputs

## Related Documentation

- [Development Workflow](./development-workflow.md) - Complete development process
- [Build PostgreSQL](./build-postgres.md) - Building PostgreSQL from source
- [Nix Directory Structure](./nix-directory-structure.md) - Project structure overview

## References

- [Nix Binary Cache Documentation](https://nixos.org/manual/nix/stable/package-management/binary-cache.html)
- [Nix Substituters](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-substituters)
- [Nix Trusted Public Keys](https://nixos.org/manual/nix/stable/command-ref/conf-file.html#conf-trusted-public-keys)
