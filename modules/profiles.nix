# Org-neutral language profiles (design D8, task 4.5) — optional devenv
# modules composable with the agentic devenv module. Ported from the
# consuming infra monorepo's devenv.nix so packaging repos stop
# hand-rolling toolchains; a repo's packaging (uv2nix, rust-overlay,
# OCI, CI) remains entirely its own — these profiles never own the
# build.
#
# Static core-eval publications (no consumer registry closure needed);
# exports.nix aliases them as devenvModules.{rust,python,polyglot,
# embedded-rust}.
{lib, ...}: let
  rust = {pkgs, ...}: {
    packages = with pkgs; [
      openssl
      pkg-config
    ];

    languages.rust = {
      enable = true;
      channel = "nightly";
      components = [
        "rustc"
        "cargo"
        "clippy"
        "rustfmt"
        "rust-analyzer"
      ];
    };

    git-hooks.hooks = {
      clippy.enable = true;
      rustfmt.enable = true;
    };

    containers = lib.mkForce {};
  };

  python = {pkgs, ...}: {
    packages = with pkgs; [
      stdenv.cc.cc
      libuv
      zlib
    ];

    languages.python = {
      enable = true;
      uv = {
        enable = true;
        sync = {
          enable = true;
          allExtras = true;
          allGroups = true;
        };
      };
    };

    git-hooks.hooks = {
      ruff.enable = true;
      ruff-format.enable = true;
      uv-check.enable = true;
    };

    containers = lib.mkForce {};
  };

  polyglot = {
    imports = [rust python];
  };

  # Embedded rust (cargo + probe-rs): tools only — flashing/building
  # stays the repo's own upstream workflow (workflow-only adoption keeps
  # working for collaborators who never enter the shell).
  embedded-rust = {pkgs, ...}: {
    packages = with pkgs; [
      probe-rs-tools
      flip-link
    ];

    languages.rust = {
      enable = true;
      channel = "stable";
      components = [
        "rustc"
        "cargo"
        "clippy"
        "rustfmt"
        "rust-analyzer"
        "llvm-tools"
      ];
    };

    git-hooks.hooks = {
      clippy.enable = true;
      rustfmt.enable = true;
    };

    containers = lib.mkForce {};
  };
in {
  # Core's own namespace (aliased by exports.nix as devenvModules.*)…
  flake.modules.devenv = {
    inherit rust python polyglot embedded-rust;
  };

  # …and the consumer's namespace via the exported flakeModule, so
  # dendritic consumers see the same modules through both channels
  # (agentic-layering spec).
  flake.modules.flake.agentic = {
    flake.modules.devenv = {
      inherit rust python polyglot embedded-rust;
    };
  };
}
