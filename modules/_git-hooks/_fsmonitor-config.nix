# Shared pin only: callers have discovered a linked worktree and enabled
# extensions.worktreeConfig. Never change the inherited global configuration.
''
  if [ "$(file_config "$git_dir/config.worktree" --get core.fsmonitor || true)" != false ]; then
    file_config "$git_dir/config.worktree" core.fsmonitor false
  fi
''
