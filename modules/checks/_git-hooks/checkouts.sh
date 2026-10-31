# Regression fixtures for checkout discovery. Run from outside all target repos.
set -euo pipefail
export HOME="$TMPDIR" PREK_HOME="$TMPDIR/prek-cache"
cd "$TMPDIR"
git init -q lookup-source
printf 'repos: []\n' > lookup-source/.pre-commit-config.yaml
git -C lookup-source add .pre-commit-config.yaml
git -C lookup-source commit -q -m config

git clone -q --no-hardlinks lookup-source before-move
(
  cd before-move
  prek install
  prek install --hook-type pre-push --config "$PWD/.pre-commit-config.yaml"
)
cp before-move/.git/hooks/pre-commit moved-hook-original
mv before-move after-move
# A moved main checkout with a relative/default config remains healthy. An
# absolute config embedded before the move is genuinely dangling, not remapped.
if "$doctor" after-move > moved-report; then echo 'missed stale absolute config' >&2; exit 1; fi
grep -qF 'before-move/.pre-commit-config.yaml' moved-report
test "$(wc -l < moved-report | tr -d ' ')" = 1
if "$doctor" --fix after-move > moved-fixed; then exit 1; fi
test ! -e after-move/.git/hooks/pre-push
cmp after-move/.git/hooks/pre-commit moved-hook-original
"$doctor" after-move > moved-clean
test ! -s moved-clean

git -C after-move worktree add -q --relative-paths --detach "$TMPDIR/relative-main"
registration="$(git -C relative-main rev-parse --absolute-git-dir)"
# Assert that this is really a relative registration, not an absolute fixture.
grep -q '^\.\./' "$registration/gitdir"
"$doctor" after-move > relative-clean
"$doctor" relative-main >> relative-clean
test ! -s relative-clean

# Test core.worktree both before and after the isolation migration.
git init -q lookup-parent
git -C lookup-parent submodule add -q "$TMPDIR/lookup-source" sub
git -C lookup-parent submodule add -q "$TMPDIR/lookup-source" orphan
git -C lookup-parent commit -q -m submodules
(
  cd lookup-parent/sub
  prek install
)
subdir="$(git -C lookup-parent/sub rev-parse --absolute-git-dir)"
git config --file "$subdir/config" --get core.worktree | grep -q '^\.\./'
"$doctor" lookup-parent > submodule-clean
test ! -s submodule-clean
cp "$subdir/hooks/pre-commit" submodule-hook-original

git -C lookup-parent/sub worktree add -q --relative-paths --detach "$TMPDIR/relative-sub"
sub_registration="$(git -C relative-sub rev-parse --absolute-git-dir)"
grep -q '^\.\./' "$sub_registration/gitdir"
(
  cd relative-sub
  "$isolate"
  prek install
)
! git config --file "$subdir/config" --get core.worktree
git config --file "$subdir/config.worktree" --get core.worktree | grep -q '^\.\./'
"$doctor" lookup-parent > migrated-clean
"$doctor" relative-sub >> migrated-clean
test ! -s migrated-clean
cmp "$subdir/hooks/pre-commit" submodule-hook-original
cp "$sub_registration/hooks/pre-commit" sub-worktree-hook-original

# A deinitialized submodule's former path is now owned by the superproject.
# Its old core.worktree is not evidence that the checkout still belongs to it.
(
  cd lookup-parent/orphan
  prek install
)
orphan_dir="$(git -C lookup-parent/orphan rev-parse --absolute-git-dir)"
printf '#!/bin/sh\ntrue\n' > "$orphan_dir/hooks/pre-push"
git -C lookup-parent submodule deinit -q -f orphan
test "$(git -C lookup-parent/orphan rev-parse --absolute-git-dir)" != "$orphan_dir"
if "$doctor" lookup-parent > orphan-report; then echo 'missed orphaned gitdir' >&2; exit 1; fi
grep -qF "$orphan_dir/hooks/pre-commit: orphaned gitdir, no checkout" orphan-report
test "$(wc -l < orphan-report | tr -d ' ')" = 1
if "$doctor" --fix lookup-parent > orphan-fixed; then exit 1; fi
test ! -e "$orphan_dir/hooks/pre-commit"
test -f "$orphan_dir/hooks/pre-push"
test -d "$orphan_dir/objects"
cmp "$subdir/hooks/pre-commit" submodule-hook-original
cmp "$sub_registration/hooks/pre-commit" sub-worktree-hook-original
"$doctor" lookup-parent > orphan-clean
test ! -s orphan-clean

# Reusing a stale registration's path for another repository must not let the
# doctor scan/remove that unrelated repository's hooks.
rm -rf relative-main
git init -q relative-main
(
  cd relative-main
  prek install --config missing.yaml
)
cp relative-main/.git/hooks/pre-commit unrelated-hook-original
"$doctor" --fix after-move > reused-clean
test ! -s reused-clean
cmp relative-main/.git/hooks/pre-commit unrelated-hook-original
