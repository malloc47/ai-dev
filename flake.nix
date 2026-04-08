{
  description = "AI coding tools with per-project sandboxing helpers and session orchestration.";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    llm-agents = {
      url = "github:numtide/llm-agents.nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      llm-agents,
    }:
    let
      supportedSystems = [
        "x86_64-linux"
        "aarch64-linux"
        "aarch64-darwin"
        "x86_64-darwin"
      ];
      forAllSystems = nixpkgs.lib.genAttrs supportedSystems;

      mkForSystem =
        system:
        let
          pkgs = import nixpkgs {
            inherit system;
            config.allowUnfree = true; # claude-code is unfree
          };
          agents = llm-agents.packages.${system};
          defaults = import ./defaults.nix { inherit pkgs; };

          # Zellij wrapper with config.kdl baked in via store path.
          zellij-ai = pkgs.writeShellApplication {
            name = "zellij-ai";
            runtimeInputs = [ pkgs.zellij ];
            text = ''
              exec zellij --config ${./zellij-config.kdl} "$@"
            '';
          };

          # Per-project sandboxing: harness+profile system with pluggable backends.
          # Each backend returns a validated mkSandbox function via mkBackend.
          backends = {
            zerobox = import ./backends/zerobox.nix { inherit pkgs; };
            nono = import ./backends/nono.nix { inherit pkgs; };
            passthrough = import ./backends/passthrough.nix { inherit pkgs; };
          };
          # Default backend: nono on all platforms (Landlock on Linux, Seatbelt on macOS).
          defaultBackend = backends.nono;

          harnessDefinitions = import ./harnesses.nix { inherit pkgs agents defaults; };
          profileDefinitions = import ./profiles.nix { inherit pkgs; };
          projectLib = import ./lib.nix {
            inherit
              pkgs
              agents
              defaults
              harnessDefinitions
              profileDefinitions
              ;
            mkSandboxUpstream = defaultBackend;
          };
        in
        {
          packages = {
            inherit zellij-ai;
            claude-code = agents.claude-code;
            opencode = agents.opencode;
            agent-deck = agents.agent-deck;
            default = pkgs.buildEnv {
              name = "ai-dev-env";
              paths = [
                agents.claude-code
                agents.opencode
                agents.agent-deck
                zellij-ai
                pkgs.zellij
              ];
            };
          };

          devShell = pkgs.mkShell {
            packages = [
              agents.claude-code
              agents.opencode
              agents.agent-deck
              zellij-ai
              pkgs.zellij
            ];
            shellHook = ''
              echo "ai-dev environment ready. Try: claude, opencode, agent-deck, zellij-ai"
            '';
          };

          apps = {
            claude = {
              type = "app";
              program = "${agents.claude-code}/bin/claude";
            };
            opencode = {
              type = "app";
              program = "${agents.opencode}/bin/opencode";
            };
            agent-deck = {
              type = "app";
              program = "${agents.agent-deck}/bin/agent-deck";
            };
            zellij-ai = {
              type = "app";
              program = "${zellij-ai}/bin/zellij-ai";
            };
            default = {
              type = "app";
              program = "${zellij-ai}/bin/zellij-ai";
            };
          };

          lib = projectLib // { inherit backends; };

          checks =
            let
              ai = projectLib // { inherit backends; };

              # Helper: build a sandboxed harness and verify the wrapper script
              # contains an expected string.  Returns a trivial derivation that
              # succeeds only if the grep matches.
              assertWrapperContains =
                name: harness: opts: needle:
                let
                  drv = ai.mkSandboxedHarness harness opts;
                in
                pkgs.runCommand "check-${name}" { } ''
                  grep -qF -- ${pkgs.lib.escapeShellArg needle} ${drv}/bin/*
                  touch $out
                '';

              # Helper: assert that a Nix expression throws at eval time.
              # We can't catch eval errors in a derivation, so instead we test
              # that the derivation *can* be built (positive tests only).
              # Platform-guard tests are eval-only and run via nix eval in CI.

            in
            {
              # -- Eval-time structure tests (built as trivial derivations) --

              # 1. All expected lib attrs exist
              lib-attrs = pkgs.runCommand "check-lib-attrs" { } ''
                expected="allowedDomains backends mergeProfiles mkProjectShell mkSandbox mkSandboxedHarness profiles resolveHarness sandboxPackages"
                actual="${builtins.concatStringsSep " " (builtins.sort builtins.lessThan (builtins.attrNames ai))}"
                if [ "$expected" != "$actual" ]; then
                  echo "Expected: $expected"
                  echo "Actual:   $actual"
                  exit 1
                fi
                touch $out
              '';

              # 2. All three backends accessible
              backend-names = pkgs.runCommand "check-backend-names" { } ''
                expected="nono passthrough zerobox"
                actual="${builtins.concatStringsSep " " (builtins.sort builtins.lessThan (builtins.attrNames ai.backends))}"
                if [ "$expected" != "$actual" ]; then
                  echo "Expected: $expected"
                  echo "Actual:   $actual"
                  exit 1
                fi
                touch $out
              '';

              # 3. All profiles accessible
              profile-names = pkgs.runCommand "check-profile-names" { } ''
                expected="aws docker github nix node python rust"
                actual="${builtins.concatStringsSep " " (builtins.sort builtins.lessThan (builtins.attrNames ai.profiles))}"
                if [ "$expected" != "$actual" ]; then
                  echo "Expected: $expected"
                  echo "Actual:   $actual"
                  exit 1
                fi
                touch $out
              '';

              # -- Build tests: nono backend (all platforms) --

              # 4. Nono-backed claude-code builds and wrapper calls nono
              nono-claude = assertWrapperContains "nono-claude" "claude-code" {
                backend = ai.backends.nono;
              } "exec nono";

              # 5. Nono-backed opencode builds and wrapper calls nono
              nono-opencode = assertWrapperContains "nono-opencode" "opencode" {
                backend = ai.backends.nono;
              } "exec nono";

              # 6. Default backend produces a nono wrapper
              default-backend-is-nono = assertWrapperContains "default-backend" "claude-code" { } "exec nono";

              # 7. Profile merging: github+python domains appear in wrapper
              profiles-merged = assertWrapperContains "profiles-merged" "claude-code" {
                profiles = [
                  ai.profiles.github
                  ai.profiles.python
                ];
              } "pypi.org";

              # 8. Passthrough returns the original package (no wrapper)
              passthrough-claude = pkgs.runCommand "check-passthrough-claude" { } ''
                name="${(ai.mkSandboxedHarness "claude-code" { backend = ai.backends.passthrough; }).name}"
                if [[ "$name" != claude-code-* ]]; then
                  echo "Expected passthrough to return original package (claude-code-*), got: $name"
                  exit 1
                fi
                touch $out
              '';

              # 9. mkProjectShell produces a shell derivation
              project-shell = pkgs.runCommand "check-project-shell" { } ''
                name="${(ai.mkProjectShell { harnesses = [ "claude-code" "opencode" ]; }).name}"
                if [ "$name" != "nix-shell" ]; then
                  echo "Expected nix-shell, got: $name"
                  exit 1
                fi
                touch $out
              '';

              # 10. mkProjectShell with backend override
              project-shell-override = pkgs.runCommand "check-project-shell-override" { } ''
                name="${(ai.mkProjectShell { backend = ai.backends.passthrough; }).name}"
                if [ "$name" != "nix-shell" ]; then
                  echo "Expected nix-shell, got: $name"
                  exit 1
                fi
                touch $out
              '';

              # 11. Nono wrapper includes closure read flags loop
              nono-closure-flags = assertWrapperContains "nono-closure" "claude-code" {
                backend = ai.backends.nono;
              } "CLOSURE_READ_FLAGS";

              # 12. Nono wrapper includes default allowed domains
              nono-default-domains = assertWrapperContains "nono-domains" "claude-code" {
                backend = ai.backends.nono;
              } "api.anthropic.com";

              # 13. unrestrictedNetwork produces bare --allow-net flag
              unrestricted-net = assertWrapperContains "unrestricted-net" "claude-code" {
                unrestrictedNetwork = true;
              } "--allow-net";
            }
            // pkgs.lib.optionalAttrs pkgs.stdenv.isLinux {
              # -- Build tests: zerobox backend (Linux only) --

              # 14. Zerobox-backed claude builds and wrapper calls zerobox
              zerobox-claude = assertWrapperContains "zerobox-claude" "claude-code" {
                backend = ai.backends.zerobox;
              } "exec zerobox";

              # 15. Zerobox wrapper includes symlink resolver
              zerobox-symlinks = assertWrapperContains "zerobox-symlinks" "claude-code" {
                backend = ai.backends.zerobox;
              } "resolve_symlinks";

              # 16. Zerobox wrapper includes NixOS system paths
              zerobox-nixos-paths = assertWrapperContains "zerobox-nixos" "claude-code" {
                backend = ai.backends.zerobox;
              } "/run/current-system";
            };
        };
    in
    {
      packages = forAllSystems (system: (mkForSystem system).packages);
      devShells = forAllSystems (system: {
        default = (mkForSystem system).devShell;
      });
      apps = forAllSystems (system: (mkForSystem system).apps);
      checks = forAllSystems (system: (mkForSystem system).checks);
      lib = forAllSystems (system: (mkForSystem system).lib) // {
        inherit forAllSystems;
      };

      templates = {
        default = {
          path = ./templates/default;
          description = "Per-project AI sandbox with claude-code and opencode";
        };
        minimal = {
          path = ./templates/minimal;
          description = "Minimal AI sandbox with just claude-code";
        };
      };

      homeManagerModules = {
        # Installs both layers — convenience for hosts that want everything
        default = import ./home-manager.nix { inherit self; };
        # Sandbox layer: raw claude-code + opencode
        sandbox = import ./sandbox.nix { inherit self; };
        # Session layer: agent-deck + zellij-ai
        session = import ./session.nix { inherit self; };
      };
    };
}
