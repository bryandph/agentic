Python projects here are **uv-first** under devenv.

- `languages.python` with `uv.enable` and `uv.sync` (allExtras +
  allGroups) — the lockfile (`uv.lock`) is the source of truth;
  never pip-install into the environment.
- Dependencies change via `uv add` / `uv remove`, run via `uv run`;
  sync happens on shell entry.
- Hooks: `ruff` + `ruff-format` + a `uv` lock consistency check.
- Packaging (when the repo ships a package) uses the pyproject-nix
  stack (`uv2nix`, `pyproject-build-systems`) in the repo's own flake
  wiring — the shell profile never owns the build.
- Beware PYTHONPATH leakage between the project env and tool-vendored
  python environments (MCP servers, CLIs): tools that ship their own
  python must run with a blanked PYTHONPATH or native-module ABI
  mismatches follow.

Deeper sources: https://devenv.sh/languages/ (python),
https://github.com/pyproject-nix/uv2nix.
