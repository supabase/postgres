# Formatting and pre-commit hooks

This repository formats code with [treefmt-nix](https://github.com/numtide/treefmt-nix) and runs the formatter as a pre-commit hook through [git-hooks.nix](https://github.com/cachix/git-hooks.nix).

## Formatting

```bash
nix fmt
```

Inside `nix develop`, `treefmt` is also on your `PATH`:

```bash
treefmt --check
```

## Pre-commit hooks

`nix develop` installs the hooks automatically. A commit that needs formatting is aborted. Review the changes, stage them, and commit again.

CI enforces formatting, so run the formatter before you push.

## Configuration

- `nix/fmt.nix`: formatters
- `nix/hooks.nix`: git hooks
