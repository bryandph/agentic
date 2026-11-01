"""Only throwaway repositories: parent-owned config rewrites and linked lifecycle."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

hooks, setup, teardown, remove, doctor = sys.argv[1:]


def run(cwd, *args):
    return subprocess.check_output(args, cwd=cwd, text=True).strip()


def git(cwd, *args):
    return run(cwd, "git", *args)


with tempfile.TemporaryDirectory() as tmp:
    root = Path(tmp).resolve()
    os.environ.update(HOME=str(root), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL=str(root / "gitconfig"))
    for key, value in (("user.name", "Fixture"), ("user.email", "fixture@example.invalid"),
                       ("init.defaultBranch", "main"), ("protocol.file.allow", "always")):
        git(root, "config", "--global", key, value)
    source, parent = root / "source", root / "parent"
    git(root, "init", str(source))
    (source / "tracked").write_text("fixture\n")
    git(source, "add", ".")
    git(source, "commit", "-m", "fixture")
    git(root, "init", str(parent))
    git(parent, "submodule", "add", str(source), "sub")
    git(parent, "commit", "-am", "submodule")
    main = parent / "sub"
    common = Path(git(main, "rev-parse", "--absolute-git-dir"))
    shared_before = (common / "config").read_text()
    assert git(root, "config", "--file", str(common / "config"), "--get", "core.worktree") == "../../../sub"
    # Match the reported state: the extension is already enabled and the
    # parent still writes core.worktree into the shared config.
    git(root, "config", "--file", str(common / "config"), "extensions.worktreeConfig", "true")
    linked = root / "linked tree"
    git(root, "--git-dir", str(common), "worktree", "add", "--detach", str(linked), "HEAD")
    linked_git = Path(git(linked, "rev-parse", "--absolute-git-dir"))
    before = git(linked, "rev-parse", "--show-toplevel")
    assert before != str(linked), before
    print(f"before --show-toplevel: {before}", flush=True)

    # Nix discovery/warm-up are tested for real by worktree-setup. Here the
    # probe must itself see the right Git checkout, before submodules run.
    fake = root / "bin"
    fake.mkdir()
    (fake / "nix").write_text('#!/bin/sh\n[ "$(git rev-parse --show-toplevel)" = "$EXPECTED_CHECKOUT" ]\n')
    (fake / "nix").chmod(0o755)
    os.environ.update(PATH=str(fake) + os.pathsep + os.environ["PATH"], EXPECTED_CHECKOUT=str(linked))
    # Set a relative backlink to exercise the same resolution as hooks doctor.
    backlink = os.path.relpath(linked / ".git", linked_git) + "\n"
    (linked_git / "gitdir").write_text("missing-checkout/.git\n")
    failed = subprocess.run([setup], cwd=linked, text=True, capture_output=True)
    assert failed.returncode != 0
    assert "setup failed at worktree-config" in failed.stderr, failed.stderr
    assert json.loads((linked_git / "workbench-setup.json").read_text())["failedStep"] == "worktree-config"
    (linked_git / "gitdir").write_text(backlink)
    run(linked, setup)
    record = json.loads((linked_git / "workbench-setup.json").read_text())
    assert record["status"] == "ok", record
    assert git(linked, "rev-parse", "--show-toplevel") == str(linked)
    assert not git(linked, "status", "--porcelain")
    print(f"after setup --show-toplevel: {git(linked, 'rev-parse', '--show-toplevel')}", flush=True)
    # No migration of shared core.worktree, nor new main config.worktree.
    assert (common / "config").read_text() == shared_before + "[extensions]\n\tworktreeConfig = true\n"
    assert not (common / "config.worktree").exists()
    assert git(root, "config", "--file", str(linked_git / "config.worktree"), "--get", "core.worktree") == str(linked)
    snapshot = (linked_git / "config.worktree").read_text()
    run(linked, hooks)
    assert (linked_git / "config.worktree").read_text() == snapshot
    git(parent, "submodule", "sync")
    git(parent, "submodule", "update", "--init", "--recursive")
    assert git(linked, "rev-parse", "--show-toplevel") == str(linked)
    assert git(main, "rev-parse", "--show-toplevel") == str(main)
    assert git(parent, "rev-parse", "--show-toplevel") == str(parent)
    for checkout in (linked, main, parent):
        assert not git(checkout, "status", "--porcelain")
    print(f"after parent update --show-toplevel: {git(linked, 'rev-parse', '--show-toplevel')}", flush=True)
    for file in (common / "config", common / "config.worktree", linked_git / "config.worktree"):
        print(f"{file}:\n{file.read_text() if file.exists() else '(absent)'}", flush=True)

    # Also support installations where the old helper migrated the main value.
    value = git(root, "config", "--file", str(common / "config"), "--get", "core.worktree")
    git(root, "config", "--file", str(common / "config.worktree"), "core.worktree", value)
    git(root, "config", "--file", str(common / "config"), "--unset", "core.worktree")
    git(root, "config", "--file", str(linked_git / "config.worktree"), "--unset", "core.worktree")
    run(linked, hooks)
    assert git(root, "config", "--file", str(linked_git / "config.worktree"), "--get", "core.worktree") == str(linked)
    for checkout in (linked, main, parent):
        assert git(checkout, "rev-parse", "--show-toplevel") == str(checkout)
    git(parent, "submodule", "update", "--init")
    assert git(root, "config", "--file", str(common / "config"), "--get", "core.worktree") == value
    for checkout in (linked, main, parent):
        assert git(checkout, "rev-parse", "--show-toplevel") == str(checkout)
        assert not git(checkout, "status", "--porcelain")
    run(linked, setup)
    assert json.loads((linked_git / "workbench-setup.json").read_text())["status"] == "ok"
    # A healthy generated hook gives doctor real context/config to validate.
    (linked / "prek.toml").write_text("repos = []\n")
    hookdir = linked_git / "hooks"
    hookdir.mkdir()
    (hookdir / "pre-commit").write_text(
        f'# File generated by prek: https://github.com/j178/prek\nPREK={sys.executable}\nexec "$PREK" --config=prek.toml\n')
    assert not run(linked, doctor)
    (linked / "prek.toml").unlink()
    (hookdir / "pre-commit").unlink()
    assert "verified:" in run(linked, teardown)
    (fake / "workbench-worktree-teardown").symlink_to(teardown)
    # The removal barrier must prove membership and cleanliness with real Git;
    # only Herdr's inventory and delegation are faked.
    (fake / "herdr").write_text(f'''#!{sys.executable}
import json, subprocess, sys
args = sys.argv[1:]
path = {str(linked)!r}
if args[:2] == ["worktree", "list"]:
    result = {{"worktrees": [{{"open_workspace_id": "fixture", "path": path}}]}}
elif args[:2] == ["workspace", "get"]:
    result = {{"workspace": {{"workspace_id": "fixture", "worktree": {{"checkout_path": path}}}}}}
elif args[:2] == ["agent", "list"]:
    result = {{"agents": []}}
elif args[:2] == ["worktree", "remove"]:
    sys.exit(subprocess.call(["git", "-C", {str(main)!r}, "worktree", "remove", path]))
else:
    sys.exit(90)
print(json.dumps({{"result": result}}))
''')
    (fake / "herdr").chmod(0o755)
    # Invoke from the linked checkout too: canonical-path and membership proof
    # must not require the main submodule checkout as CWD.
    result = json.loads(run(linked, remove, "--workspace", "fixture", "--worktree", str(linked)))
    assert result["status"] == "removed", result
    assert result["teardown"]["status"] == "passed", result
    assert not linked.exists()
    assert git(main, "rev-parse", "--show-toplevel") == str(main)
    assert not git(parent, "status", "--porcelain")
