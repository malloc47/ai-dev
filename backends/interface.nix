# Backend interface: validates that a sandbox backend meets the required contract.
#
# mkBackend takes a backend definition and returns a validated mkSandbox function.
# The backend definition must declare its supported platforms and capabilities.
# The platform check is deferred to call time so backends can be inspected on
# any platform without triggering the assertion.
{ pkgs }:
{
  # Wrap a backend's mkSandbox with platform validation.
  # backend : { supportedPlatforms : [string], mkSandbox : attrs -> derivation }
  # Returns: attrs -> derivation  (the validated mkSandbox function)
  mkBackend =
    {
      name,
      supportedPlatforms,
      mkSandbox,
    }:
    let
      currentPlatform = pkgs.stdenv.hostPlatform.system;
      platformSupported = builtins.elem currentPlatform supportedPlatforms;
    in
    args:
    assert
      platformSupported
      || throw "${name}: unsupported platform ${currentPlatform}. Supported: ${builtins.concatStringsSep ", " supportedPlatforms}";
    mkSandbox args;
}
