# nono backend: Landlock (Linux) / Seatbelt (macOS) sandboxing.
#
# Uses the nono package from nixpkgs.  Supports all platforms.
# macOS Keychain access is handled via nono's --secrets flag.
#
# Limitations vs zerobox:
# - No per-domain network filtering (--net-block is all-or-nothing)
# - No --env flag; environment is inherited from the parent shell
{ pkgs }:
let
  interface = import ./interface.nix { inherit pkgs; };

  # nono uses --read/--write/--allow (not --allow-read/--allow-write)
  mkReadFlags = paths: builtins.concatStringsSep " " (map (p: ''--read "${p}"'') paths);
  mkWriteFlags = paths: builtins.concatStringsSep " " (map (p: ''--allow "${p}"'') paths);
in
interface.mkBackend {
  name = "nono";
  supportedPlatforms = [
    "x86_64-linux"
    "aarch64-linux"
    "x86_64-darwin"
    "aarch64-darwin"
  ];
  mkSandbox =
    {
      pkg,
      binName,
      outName,
      packages ? [ ],
      allowRead ? [ ],
      allowWrite ? [ ],
      # nono has no per-domain filtering.  true = allow network (default);
      # [] or list = block all network via --net-block.
      allowNet ? [ ],
      env ? { },
    }:
    let
      pathStr = pkgs.lib.makeBinPath (packages ++ [ pkg ]);

      # Network: nono only supports all-or-nothing.
      # allowNet == true or non-empty list → allow; [] → block.
      netFlag = if allowNet == true || allowNet != [ ] then "" else "--net-block";

      # Environment variables: nono inherits the parent environment, so we
      # export them in the wrapper script before exec.
      envExports = builtins.concatStringsSep "\n" (
        map (name: ''export ${name}=${pkgs.lib.escapeShellArg (builtins.toJSON env.${name})}'') (
          builtins.attrNames env
        )
      );
    in
    pkgs.writeShellApplication {
      name = outName;
      runtimeInputs = [
        pkgs.nono
        pkgs.coreutils
      ];
      text = ''
        # Ensure directories exist (skip paths that are already files)
        ${builtins.concatStringsSep "\n" (
          map (p: ''if [ ! -f "${p}" ]; then mkdir -p "${p}"; fi'') allowWrite
        )}
        ${builtins.concatStringsSep "\n" (
          map (p: ''if [ ! -f "${p}" ]; then mkdir -p "${p}"; fi'') allowRead
        )}

        REAL_TMPDIR="''${TMPDIR:-/tmp}"

        # Set PATH and any extra env vars before entering the sandbox
        export PATH="${pathStr}"
        ${envExports}

        # shellcheck disable=SC2086
        exec nono run \
          --allow-cwd \
          --allow "$REAL_TMPDIR" \
          --allow /tmp \
          --read /etc \
          --read /nix/store \
          --read /nix/var \
          ${mkWriteFlags allowWrite} \
          ${mkReadFlags allowRead} \
          ${netFlag} \
          --exec \
          -- ${pkg}/bin/${binName} "$@"
      '';
    };
}
