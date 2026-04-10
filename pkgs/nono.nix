{
  lib,
  rustPlatform,
  fetchFromGitHub,

  pkg-config,

  dbus,
}:

rustPlatform.buildRustPackage (finalAttrs: {
  pname = "nono";
  version = "0.30.1";

  src = fetchFromGitHub {
    owner = "always-further";
    repo = "nono";
    tag = "v${finalAttrs.version}";
    hash = "sha256-uk0L5HOhVEUOvzeKEyZNfc9EOGu4igbTc5nhTTYQmDg=";
  };

  cargoHash = "sha256-Gi8Yu+m7WbI+6jMg1I+wXRPlIBj3IrrXPRvgJJ2tQRs=";

  nativeBuildInputs = [
    pkg-config
  ];

  buildInputs = [
    dbus
  ];

  # Upstream test failure in v0.30.1:
  # capability_ext::tests::test_from_profile_allow_file_falls_back_to_exact_directory_when_present
  doCheck = false;

  meta = {
    description = "Secure, kernel-enforced sandbox for AI agents, MCP and LLM workloads";
    homepage = "https://github.com/always-further/nono";
    changelog = "https://github.com/always-further/nono/blob/${finalAttrs.src.rev}/CHANGELOG.md";
    license = lib.licenses.asl20;
    maintainers = with lib.maintainers; [
      jk
    ];
    mainProgram = "nono";
    platforms = lib.platforms.linux ++ lib.platforms.darwin;
  };
})
