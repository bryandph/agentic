# Per-worktree hook isolation, shared by setup and the standalone devenv module.
pkgs:
pkgs.writeShellApplication {
  name = "agentic-worktree-hooks";
  runtimeInputs = [pkgs.git pkgs.coreutils];
  text = ''
    # The inherited relative core.worktree may even point at a nonexistent
    # directory. Override it only for metadata discovery; never persist PWD.
    git_dir="$(GIT_WORK_TREE="$PWD" git rev-parse --absolute-git-dir 2>/dev/null)" || exit 0
    common_dir="$(GIT_WORK_TREE="$PWD" git rev-parse --path-format=absolute --git-common-dir)"
    [ "$git_dir" != "$common_dir" ] || exit 0
    # A parent submodule update can rewrite shared core.worktree at any time.
    # Never move/unset it: pin this checkout in its own config instead, using
    # the registration backlink rather than the potentially wrong top level.
    file_config() { GIT_WORK_TREE="$PWD" git config --file "$@"; }
    if file_config "$common_dir/config" --get core.worktree >/dev/null ||
       file_config "$common_dir/config.worktree" --get core.worktree >/dev/null; then
      IFS= read -r gitfile < "$git_dir/gitdir"
      if [[ "$gitfile" != /* ]]; then gitfile="$git_dir/$gitfile"; fi
      gitfile="$(realpath -e -- "$gitfile")"
      checkout="$(dirname -- "$gitfile")"
      file_config "$git_dir/config.worktree" core.worktree "$checkout"
    fi
    if [ "$(file_config "$common_dir/config" --get extensions.worktreeConfig || true)" != true ]; then
      # Bare common repositories still need the main-only bare flag migrated.
      if [ "$(file_config "$common_dir/config" --get core.bare || true)" = true ]; then
        file_config "$common_dir/config.worktree" core.bare true
        file_config "$common_dir/config" --unset core.bare
      fi
      file_config "$common_dir/config" extensions.worktreeConfig true
    fi
    ${import ./_fsmonitor-config.nix}
    if [ "$(git config --worktree --get core.hooksPath || true)" != "$git_dir/hooks" ]; then
      git config --worktree core.hooksPath "$git_dir/hooks"
    fi
  '';
}
