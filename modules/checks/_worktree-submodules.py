"""BPH-88: excluded, recursive, skipped and failed submodule setup records."""

import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile

setup, disabled = sys.argv[1:]


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
    fake = root / "bin"
    fake.mkdir()
    (fake / "nix").write_text("#!/bin/sh\nexit 0\n")
    (fake / "nix").chmod(0o755)
    os.environ["PATH"] = str(fake) + os.pathsep + os.environ["PATH"]

    def source(name):
        repo = root / name
        git(root, "init", str(repo))
        (repo / "tracked").write_text("fixture\n")
        git(repo, "add", ".")
        git(repo, "commit", "-m", "fixture")
        return repo

    leaf = source("leaf")
    recursive = source("recursive")
    git(recursive, "submodule", "add", str(leaf), "nested")
    git(recursive, "commit", "-am", "nested")

    def checkout(name):
        parent = source(name)
        git(parent, "submodule", "add", str(recursive), "selected space")
        git(parent, "submodule", "add", str(leaf), "excluded space")
        git(parent, "commit", "-am", "submodules")
        linked = root / (name + " linked")
        git(parent, "worktree", "add", "--detach", str(linked))
        return parent, linked

    def invoke(name, linked, command=setup, success=True, initialized=None, skipped=None):
        result = subprocess.run([command, "--worktree", str(linked)], cwd=root, text=True, capture_output=True)
        record = json.loads((Path(git(linked, "rev-parse", "--absolute-git-dir")) / "workbench-setup.json").read_text())
        print(name + ": " + json.dumps(record, sort_keys=True), flush=True)
        assert (result.returncode == 0) == success, (result, record)
        assert record["status"] == ("ok" if success else "failed"), record
        assert record["failedStep"] == (None if success else "submodules"), record
        assert record["submodules"] == {
            "configured": command == setup,
            "initialized": initialized or [],
            "excluded": ["excluded space"] if command == setup else [],
            "skipped": skipped,
        }, record
        if not success:
            assert "setup failed at submodules" in result.stderr, result.stderr
        return result

    parent, linked = checkout("excluded")
    invoke("excluded-recursive", linked, initialized=["selected space"])
    assert (linked / "selected space/nested/tracked").is_file()
    assert not (linked / "excluded space/.git").exists()
    gitdir = Path(git(linked, "rev-parse", "--absolute-git-dir"))
    assert not (gitdir / "modules/excluded space").exists()
    assert git(linked, "submodule", "status", "--", "excluded space").startswith("-")
    invoke("idempotent", linked, initialized=["selected space"])

    parent, linked = checkout("off")
    result = invoke("trait-off", linked, command=disabled, skipped="trait-off")
    assert result.stderr.count("WARNING:") == 1, result.stderr
    assert "agentic.worktree.traits.submodules" in result.stderr, result.stderr
    assert not (linked / "selected space/.git").exists()
    assert not (linked / "excluded space/.git").exists()

    parent, linked = checkout("unreachable")
    git(parent, "config", "submodule.selected space.url", str(root / "missing-source"))
    invoke("unreachable", linked, success=False)

    parent, linked = checkout("no-op")
    # Git can report success while intentionally skipping initialization. The
    # postcondition, not the command's exit code, must reject this outcome.
    git(parent, "config", "submodule.selected space.update", "none")
    result = invoke("configured-not-initialized", linked, success=False)
    assert "submodules not initialized:" in result.stderr, result.stderr
    assert "selected" in result.stderr, result.stderr

    parent, linked = checkout("already-excluded")
    git(linked, "submodule", "update", "--init", "--", "excluded space")
    result = invoke("excluded-already-initialized", linked, success=False,
                    initialized=["selected space", "excluded space"])
    assert "excluded submodules initialized:" in result.stderr, result.stderr

    parent = source("only-excluded")
    git(parent, "submodule", "add", str(recursive), "excluded space")
    git(parent, "commit", "-am", "excluded only")
    linked = root / "only-excluded-linked"
    git(parent, "worktree", "add", "--detach", str(linked))
    invoke("all-excluded", linked)
    assert not (linked / "excluded space/.git").exists()
    assert not (linked / "excluded space/nested/.git").exists()
    gitdir = Path(git(linked, "rev-parse", "--absolute-git-dir"))
    assert not (gitdir / "modules").exists()

    parent = source("empty")
    linked = root / "empty-linked"
    git(parent, "worktree", "add", "--detach", str(linked))
    invoke("no-gitmodules", linked, skipped="no-gitmodules")
    invoke("off-no-gitmodules", linked, command=disabled, skipped="no-gitmodules")
