# Contributing

Welcome! Here are some tips to help you get started, especially if you're new to Nix:

- Always run `treefmt` (or `nix fmt`, which is an alias) before committing your files. This ensures your code is properly formatted (otherwise, the CI will complain).

- You can automate formatting checks locally by installing a git pre-commit hook with `pre-commit install`.

- The default Nix devshell provides `pre-commit`, `treefmt`, and `nixpkgs-fmt`. Enter the devshell with `nix develop` to have these binaries in your PATH.

- You can automate load/unloading the devshell when entering/leaving the project directory using [`direnv`](./direnv.md).

For more details on the development process, check out [./development-workflow.md](./development-workflow.md).
