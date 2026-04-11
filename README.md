# ai-dev

Portable subflake for per-project AI agent sandboxing. Installs `claude-code` and `opencode` via `programs.ai-sandbox`; exposes `lib` helpers for sandboxing with pluggable backends (nono, zerobox, passthrough).

## System-level install

### NixOS / home-manager (declarative)

```nix
# flake inputs
inputs.ai-dev.url = "github:malloc47/ai-dev";
```

```nix
# home-manager config
imports = [ inputs.ai-dev.homeManagerModules.default ];
programs.ai-sandbox.enable = true;  # claude-code, opencode
```

### Non-NixOS Linux / standalone nix

```bash
nix profile install github:malloc47/ai-dev
```

## Per-project sandbox

Scaffold a project with a template:

```bash
nix flake init -t github:malloc47/ai-dev          # default (claude + opencode)
nix flake init -t github:malloc47/ai-dev#minimal  # claude only
```

Or add a `flake.nix` manually:

```nix
{
  inputs.ai-dev.url = "github:malloc47/ai-dev";

  outputs = { ai-dev, ... }:
    ai-dev.lib.forAllSystems (system:
      let ai = ai-dev.lib.${system}; in {
        devShells.${system}.default = ai.mkProjectShell {
          harnesses = [ "claude-code" "opencode" ];
          profiles = with ai.profiles; [ github python ];
        };
      });
}
```

Then `nix develop` gives you sandboxed `claude` and `opencode` scoped to that project. Agents run inside a nono sandbox (Landlock on Linux, Seatbelt on macOS) with per-domain network filtering. On Linux, the zerobox backend (bwrap+seccomp) is also available.

### Harnesses

A harness wraps an AI agent with sandbox-appropriate defaults (state dirs, domains, CLI flags). Built-in harnesses:

| Harness | Binary | Auto-configured |
|---------|--------|-----------------|
| `"claude-code"` | `claude` | `~/.claude`, `~/.config/claude`, Anthropic domains, `--add-dir` for extra state dirs |
| `"opencode"` | `opencode` | `~/.opencode`, `~/.config/opencode`, OpenAI domains |

You can also pass a raw derivation as a harness for generic sandboxing.

### Profiles

Profiles bundle packages, domains, and state paths for a tool ecosystem:

| Profile | Packages | Domains | State |
|---------|----------|---------|-------|
| `github` | `gh` | github.com, api.github.com | `~/.config/gh` |
| `python` | `python3`, `pip` | pypi.org, files.pythonhosted.org | `~/.cache/pip` |
| `node` | `nodejs` | registry.npmjs.org, registry.yarnpkg.com | `~/.npm`, `node_modules` |
| `rust` | `rustc`, `cargo` | crates.io, static.crates.io, index.crates.io | `~/.cargo`, `target` |
| `aws` | `awscli2` | sts.amazonaws.com | `~/.aws` |
| `docker` | `docker-client` | — | `~/.docker` |
| `nix` | `nix`, `nixfmt-rfc-style` | cache.nixos.org | — |

### Available lib functions

**`mkProjectShell`** — returns a `mkShell` with sandboxed harnesses:

```nix
mkProjectShell {
  harnesses ? [ "claude-code" "opencode" ];
  profiles ? [];               # composable tool profiles
  unrestrictedNetwork ? false; # true = allow all network; false = domain allowlist
  unrestrictedHarness ? false; # --dangerously-skip-permissions for claude
  domains ? [];                # domains to add to the allowlist
  packages ? [];               # packages available inside the sandbox
  allowWrite ? [];             # additional read-write directories (also passed as --add-dir to claude)
  allowRead ? [];              # additional read-only paths
  env ? {};                    # environment variables passed into the sandbox
  shellPackages ? [];          # packages added to the devShell (outside sandbox)
  backend ? null;              # sandbox backend override (default: nono)
}
```

**`mkSandboxedHarness`** — lower-level, returns a single sandboxed package:

```nix
mkSandboxedHarness "claude-code" {
  profiles ? [];
  unrestrictedNetwork ? false;
  unrestrictedHarness ? false;
  domains ? [];
  packages ? [];
  allowWrite ? [];
  allowRead ? [];
  env ? {};
  backend ? null;
}
```

**`profiles`** — the built-in profile set, for use with `with ai.profiles; [ github python ]`.

**`mkSandbox`** — the active backend's sandbox function, for full control.

**`sandboxPackages`** / **`allowedDomains`** — the default lists, for inspection or extension.

**`forAllSystems`** — available at `ai-dev.lib.forAllSystems` for project flakes to avoid hardcoding system strings.

### Default allowed domains

- `api.anthropic.com`, `platform.claude.com`, `console.anthropic.com`, `statsig.anthropic.com`, `sentry.io`
- `api.openai.com`
- `github.com`, `api.github.com`, `objects.githubusercontent.com`, `registry.npmjs.org`

### Default sandbox packages

coreutils, git, ripgrep, fd, gnused, gnugrep, findutils, jq, which, nodejs, curl, openssh, diffutils, patch, gnutar, gzip

