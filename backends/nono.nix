# nono backend: Landlock (Linux) / Seatbelt (macOS) sandboxing with
# Layer 7 endpoint filtering and credential proxy.
#
# Uses the nono package from nixpkgs.  Supports all platforms.
# macOS support includes credential proxy for Keychain access.
{ pkgs }:
let
  interface = import ./interface.nix { inherit pkgs; };

  # nono CLI flag generation helpers
  mkReadFlags = paths: builtins.concatStringsSep " " (map (p: ''--allow-read "${p}"'') paths);
  mkWriteFlags = paths: builtins.concatStringsSep " " (
    map (p: ''--allow-write "${p}" --allow-read "${p}"'') paths
  );
  mkNetFlags =
    allowNet:
    if allowNet == true then
      "--allow-net"
    else
      builtins.concatStringsSep " " (map (d: ''--allow-net "${d}"'') allowNet);
  mkEnvFlags =
    env:
    builtins.concatStringsSep " " (
      map (name: ''--env "${name}=${builtins.toJSON env.${name}}"'') (builtins.attrNames env)
    );
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
      allowNet ? [ ],
      env ? { },
    }:
    let
      pathStr = pkgs.lib.makeBinPath (packages ++ [ pkg ]);
      closurePaths = pkgs.writeClosure (packages ++ [ pkg ]);
    in
    pkgs.writeShellApplication {
      name = outName;
      runtimeInputs = [
        pkgs.nono
        pkgs.coreutils
      ];
      text = ''
        CWD=$(pwd)

        # Ensure paths exist (skip files that already exist)
        ${builtins.concatStringsSep "\n" (
          map (p: ''if [ ! -f "${p}" ]; then mkdir -p "${p}"; fi'') allowWrite
        )}
        ${builtins.concatStringsSep "\n" (
          map (p: ''if [ ! -f "${p}" ]; then mkdir -p "${p}"; fi'') allowRead
        )}

        # Build --allow-read flags for nix store closure
        CLOSURE_READ_FLAGS=""
        while IFS= read -r storePath; do
          CLOSURE_READ_FLAGS="$CLOSURE_READ_FLAGS --allow-read $storePath"
        done < ${closurePaths}

        REAL_TMPDIR="''${TMPDIR:-/tmp}"

        # shellcheck disable=SC2086
        exec nono \
          --allow-read "$CWD" \
          --allow-write "$CWD" \
          --allow-read /etc \
          --allow-read /nix/store \
          --allow-read /nix/var \
          --allow-read "$REAL_TMPDIR" \
          --allow-write "$REAL_TMPDIR" \
          --allow-read /tmp \
          --allow-write /tmp \
          $CLOSURE_READ_FLAGS \
          ${mkWriteFlags allowWrite} \
          ${mkReadFlags allowRead} \
          ${mkNetFlags allowNet} \
          ${mkEnvFlags env} \
          --env "PATH=${pathStr}" \
          --env "HOME=$HOME" \
          --env "TERM=$TERM" \
          --env "TMPDIR=$REAL_TMPDIR" \
          -- ${pkg}/bin/${binName} "$@"
      '';
    };
}
