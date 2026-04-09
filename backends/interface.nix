# Backend interface: validates that a sandbox backend meets the required contract.
#
# mkBackend takes a backend definition and returns a callable attrset.
# The backend definition must declare its supported platforms and capabilities.
# The platform check is deferred to call time so backends can be inspected on
# any platform without triggering the assertion.
#
# The returned value is an attrset with __functor (so it behaves like a function)
# plus optional metadata (e.g. `package` for the sandbox tool binary).
{ pkgs }:
{
  # Wrap a backend's mkSandbox with platform validation.
  # backend : { supportedPlatforms : [string], mkSandbox : attrs -> derivation, package? : derivation }
  # Returns: attrset with __functor (callable) + metadata
  mkBackend =
    {
      name,
      supportedPlatforms,
      mkSandbox,
      package ? null,
    }:
    let
      currentPlatform = pkgs.stdenv.hostPlatform.system;
      platformSupported = builtins.elem currentPlatform supportedPlatforms;
    in
    {
      __functor =
        self: args:
        assert
          platformSupported
          || throw "${name}: unsupported platform ${currentPlatform}. Supported: ${builtins.concatStringsSep ", " supportedPlatforms}";
        mkSandbox args;
      inherit name package;
    };
}
