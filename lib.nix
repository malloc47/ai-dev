# Composition engine: merges harnesses and profiles into sandboxed derivations.
{
  pkgs,
  agents,
  mkSandboxUpstream,
  defaults,
  harnessDefinitions,
  profileDefinitions,
}:
let
  # Fold a list of profiles into a single aggregate config.
  mergeProfiles =
    profiles:
    builtins.foldl'
      (acc: p: {
        packages = acc.packages ++ (p.packages or [ ]);
        domains = acc.domains ++ (p.domains or [ ]);
        allowWrite = acc.allowWrite ++ (p.allowWrite or [ ]);
        allowRead = acc.allowRead ++ (p.allowRead or [ ]);
      })
      {
        packages = [ ];
        domains = [ ];
        allowWrite = [ ];
        allowRead = [ ];
      }
      profiles;

  # Resolve a harness spec (string name or raw derivation) to a definition.
  resolveHarness =
    h:
    if builtins.isString h then
      harnessDefinitions.${h}
        or (throw "Unknown harness: ${h}. Known: ${builtins.concatStringsSep ", " (builtins.attrNames harnessDefinitions)}")
    else
      # Bare derivation: generic wrapper with no special state/flags
      {
        pkg = h;
        binName = h.pname or h.name;
        outName = h.pname or h.name;
        allowWrite = [ ];
        allowWriteFiles = [ ];
        domains = [ ];
        packages = [ ];
        mkWrappedPkg =
          {
            writePaths ? [ ],
            unrestricted ? false,
          }:
          h;
      };

  # Build a single sandboxed harness derivation.
  mkSandboxedHarness =
    harnessSpec:
    {
      profiles ? [ ],
      domains ? [ ],
      packages ? [ ],
      allowWrite ? [ ],
      allowRead ? [ ],
      env ? { },
      # true = unrestricted network; false = restrict to domain allowlist.
      unrestrictedNetwork ? false,
      unrestrictedHarness ? false,
      # Sandbox backend function.  null = use the flake-level default.
      backend ? null,
    }:
    let
      sandbox = if backend != null then backend else mkSandboxUpstream;
      harness = resolveHarness harnessSpec;
      merged = mergeProfiles profiles;

      allAllowWrite = harness.allowWrite ++ merged.allowWrite ++ allowWrite;
      allAllowWriteFiles = (harness.allowWriteFiles or [ ]);
      allAllowRead = merged.allowRead ++ allowRead;
      allDomains = defaults.allowedDomains ++ harness.domains ++ merged.domains ++ domains;
      allPackages = defaults.sandboxPackages ++ harness.packages ++ merged.packages ++ packages;

      wrappedPkg = harness.mkWrappedPkg {
        writePaths = allowWrite;
        unrestricted = unrestrictedHarness;
      };
    in
    sandbox {
      pkg = wrappedPkg;
      inherit (harness) binName outName;
      packages = allPackages;
      allowWrite = allAllowWrite;
      allowWriteFiles = allAllowWriteFiles;
      allowRead = allAllowRead;
      allowNet = if unrestrictedNetwork then true else allDomains;
      inherit env;
    };

  # High-level: produce a devShell from a list of harnesses.
  mkProjectShell =
    {
      harnesses ? [
        "claude-code"
        "opencode"
      ],
      profiles ? [ ],
      domains ? [ ],
      packages ? [ ],
      allowWrite ? [ ],
      allowRead ? [ ],
      env ? { },
      shellPackages ? [ ],
      unrestrictedNetwork ? false,
      unrestrictedHarness ? false,
      # Sandbox backend function.  null = use the flake-level default.
      backend ? null,
    }:
    let
      activeBackend = if backend != null then backend else mkSandboxUpstream;
      sandboxedBinaries = map (
        h:
        mkSandboxedHarness h {
          inherit
            profiles
            domains
            packages
            allowWrite
            allowRead
            env
            unrestrictedNetwork
            unrestrictedHarness
            backend
            ;
        }
      ) harnesses;
      backendToolPackages =
        if activeBackend ? package && activeBackend.package != null then
          [ activeBackend.package ]
        else
          [ ];
    in
    pkgs.mkShell {
      packages = sandboxedBinaries ++ backendToolPackages ++ shellPackages;
    };

in
{
  inherit
    mkProjectShell
    mkSandboxedHarness
    mergeProfiles
    resolveHarness
    ;
  inherit (defaults) sandboxPackages allowedDomains;
  profiles = profileDefinitions;
  mkSandbox = mkSandboxUpstream;
}
