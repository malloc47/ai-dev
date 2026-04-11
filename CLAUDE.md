# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Overview

Nix flake providing AI coding tools (claude-code, opencode) with per-project sandboxing via pluggable backends. Consumed as a flake input by downstream configuration repos.

## Commands

```bash
# Run all checks (14 on Darwin, 17 on Linux)
nix flake check

# Run checks for all platforms (requires multi-arch)
nix flake check --all-systems

# Evaluate lib exports
nix eval .#lib.aarch64-darwin --apply 'lib: builtins.attrNames lib'

# Build a sandboxed harness for inspection
nix build --impure --expr '(builtins.getFlake "path:'$(pwd)'").lib.aarch64-darwin.mkSandboxedHarness "claude-code" {}'
cat result/bin/claude  # inspect the generated wrapper script

# Test zerobox platform guard (should fail on Darwin, succeed on Linux)
nix eval .#lib.aarch64-darwin --apply 'lib: lib.mkSandboxedHarness "claude-code" { backend = lib.backends.zerobox; }'
```

## Architecture

- **Sandbox layer** (`programs.ai-sandbox`): installs claude-code and opencode; exposes `lib` for per-project sandboxing

### Composition flow

```
mkProjectShell / mkSandboxedHarness  (lib.nix)
  ├── resolves harness spec → harness definition  (harnesses.nix)
  ├── merges profiles → aggregate {packages, domains, allowWrite, allowRead}  (profiles.nix)
  ├── merges with defaults  (defaults.nix)
  └── calls backend mkSandbox → writeShellApplication wrapper
        └── backend validated via mkBackend  (backends/interface.nix)
```

### Backend interface

`backends/interface.nix` defines `mkBackend` which returns an attrset with `__functor` (callable like a function) plus `name` and `package` metadata. Platform validation is deferred to call time — backends can be inspected/referenced on any platform without triggering assertions.

Each backend's `mkSandbox` receives: `{ pkg, binName, outName, packages, allowRead, allowWrite, allowNet, env }` and returns a `writeShellApplication` derivation (or the original pkg for passthrough).

### Three backends

| Backend | Platforms | Network filtering | Tool |
|---------|-----------|-------------------|------|
| **nono** (default) | all | per-domain (`--allow-domain`) | `pkgs.nono` |
| **zerobox** | Linux only | per-domain (`--allow-net`) | custom from `pkgs/zerobox.nix` |
| **passthrough** | all | none (no sandbox) | none |

### Key design decisions

- **nono is the default on all platforms.** It uses Landlock on Linux and Seatbelt on macOS.
- **Wrappers use absolute store paths** for the backend binary (e.g., `${pkgs.nono}/bin/nono`) because the wrapper intentionally overwrites `$PATH` to control what the sandboxed process sees.
- **`mkProjectShell` injects the backend tool** (nono or zerobox) into the devShell so users can test it directly.
- **Harness `mkWrappedPkg`** handles tool-specific CLI flags (e.g., claude's `--add-dir`, `--dangerously-skip-permissions`) as an inner wrapper before the sandbox wrapper is applied.
- **Zerobox resolves symlink chains** for NixOS paths (`/run/current-system`, `/etc/ssl`, etc.) and scans Nix store closures via `writeClosure`.

## Checks

The `checks` flake output contains build-time assertions. When adding a new backend or feature, add a corresponding check. The `assertWrapperContains` helper in `flake.nix` builds a sandboxed harness and greps its wrapper script for an expected string. Linux-only checks are gated behind `pkgs.lib.optionalAttrs pkgs.stdenv.isLinux`.

## Nono CLI reference

Correct flags (not the same as zerobox):
- Filesystem: `--read`, `--allow` (read-write), `--allow-cwd`, `--allow-file`, `--read-file`
- Network: `--block-net` (block all), `--allow-domain <domain>` (per-domain filtering), `--network-profile <name>`
- Profiles: `--profile <name>` (built-in: `claude-code`, `codex`, `opencode`, `developer`, `minimal`)
- No `--env` flag — environment is inherited from the parent shell
- Supervised mode is the default; no `--exec` flag needed for interactive/TTY apps
