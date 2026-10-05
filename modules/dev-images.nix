# Workbench dev-environment images (OpenSpec `distributable-dev-environments`
# in nixspace, BPH-39). The builder (`_dev-images/builder.nix`) is exported as
# `lib.devImages`, a function of the consumer's `pkgs`, so consumers keep
# their overlays and pins:
#
#   images = inputs.agentic.lib.devImages {
#     inherit pkgs lib;
#     nix2container = inputs.nix2container.packages.${system};
#     harnesses = {inherit (inputs.llm-agents.packages.${system}) claude-code codex pi;};
#   };
#   images.mkDevImage { name = "registry/path/dev-nix"; withNix = true; ... };
#
# This flake also builds the generic, org-neutral `dev-base` and `dev-nix`
# (public endpoints only) and ships the `dev-verify`, `dev-image-repo` and
# `dev-image-publish` tools as packages and apps.
{
  inputs,
  lib,
  ...
}: {
  flake.lib.devImages = import ./_dev-images/builder.nix;
  # Changes whenever the builder does; part of a warm image's identity.
  flake.lib.devImagesRecipe = builtins.hashFile "sha256" ./_dev-images/builder.nix;

  perSystem = {
    pkgs,
    system,
    ...
  }: let
    images = import ./_dev-images/builder.nix {
      inherit pkgs lib;
      nix2container = inputs.nix2container.packages.${system};
      harnesses = {inherit (inputs.llm-agents.packages.${system}) claude-code codex pi;};
    };
    app = drv: description: {
      type = "app";
      program = lib.getExe drv;
      meta = {inherit description;};
    };
  in {
    packages =
      {
        dev-verify = images.devVerify;
        dev-image-repo = images.devImageRepo;
        dev-image-publish = images.devImagePublish;
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        dev-base = images.mkDevImage {name = "dev-base";};
        dev-nix = images.mkDevImage {
          name = "dev-nix";
          withNix = true;
        };
      };

    apps = {
      dev-image-repo = app images.devImageRepo "Build/publish a repository's warm dev environment image";
      dev-image-publish = app images.devImagePublish "Publish a dev image package as a multi-arch OCI index";
    };
  };
}
