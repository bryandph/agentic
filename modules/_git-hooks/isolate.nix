# Per-worktree hook isolation, shared by setup and the standalone devenv module.
pkgs:
pkgs.writeShellApplication {
  name = "agentic-worktree-hooks";
  runtimeInputs = [pkgs.git];
  text = ''
    git_dir="$(git rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
    common_dir="$(git rev-parse --path-format=absolute --git-common-dir)"
    [ "$git_dir" != "$common_dir" ] || exit 0
    if [ "$(git config --file "$common_dir/config" --get extensions.worktreeConfig || true)" != true ]; then
      for key in core.worktree core.bare; do
        value="$(git config --file "$common_dir/config" --get "$key" || true)"
        if [ -n "$value" ] && { [ "$key" = core.worktree ] || [ "$value" = true ]; }; then
          git config --file "$common_dir/config.worktree" "$key" "$value"
          git config --file "$common_dir/config" --unset "$key"
        fi
      done
      git config --file "$common_dir/config" extensions.worktreeConfig true
    fi
    if [ "$(git config --worktree --get core.hooksPath || true)" != "$git_dir/hooks" ]; then
      git config --worktree core.hooksPath "$git_dir/hooks"
    fi
  '';
}
