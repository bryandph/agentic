# Project templates (agentic-project-template spec, task 7.1): one
# `nix flake init -t` away from a workflow-complete repo. Variants
# compose a language profile with the agentic devenv module — they
# never own the project's packaging; `adopt` is the workflow-only mode
# for existing repos (including non-flake ones): a dev-shell-only flake
# + .envrc, the build untouched.
{
  flake.templates = rec {
    default = {
      path = ../templates/default;
      description = "Workflow-complete project: devenv + agentic registry (MCP, agents, knowledge, workmux) + openspec scaffold";
    };
    rust = {
      path = ../templates/rust;
      description = "default + the rust language profile (nightly toolchain, clippy/rustfmt hooks)";
    };
    python = {
      path = ../templates/python;
      description = "default + the python/uv profile (uv sync, ruff hooks)";
    };
    polyglot = {
      path = ../templates/polyglot;
      description = "default + rust and python profiles";
    };
    embedded = {
      path = ../templates/embedded;
      description = "default + the embedded-rust profile (stable + llvm-tools, probe-rs)";
    };
    adopt = {
      path = ../templates/adopt;
      description = "Workflow-only adoption for existing repos (incl. non-flake): dev-shell-only flake + .envrc, build untouched";
    };
    agentic = default;
  };
}
