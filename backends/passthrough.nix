# Passthrough backend: no sandboxing, returns the package as-is.
# Used on platforms where no sandbox backend is available (e.g. macOS).
{ pkgs }:
let
  interface = import ./interface.nix { inherit pkgs; };
in
interface.mkBackend {
  name = "passthrough";
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
      allowWriteFiles ? [ ],
      allowNet ? [ ],
      env ? { },
    }:
    pkg;
}
