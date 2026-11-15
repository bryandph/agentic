"""Offline real-Git fixtures; the only Herdr here is a PATH fake."""

import hashlib
import json
import os
from pathlib import Path
import subprocess
import shutil
import sys
import tempfile

good, bad, skipped = sys.argv[1:]
# macOS /tmp is /private/tmp; compare Herdr's canonical checkout paths.
root = Path(tempfile.mkdtemp()).resolve()
os.environ.update(HOME=str(root / "home"), GIT_CONFIG_NOSYSTEM="1", GIT_CONFIG_GLOBAL="/dev/null")
(root / "home").mkdir()


def git(cwd, *args):
    return subprocess.check_output(["git", "-C", str(cwd), *args], stderr=subprocess.PIPE).decode().strip()


fake = root / "bin"
fake.mkdir()
(fake / "herdr").write_text('''#!/usr/bin/env python3
import json, os, subprocess, sys
args = sys.argv[1:]
state = json.load(open(os.environ["STATE"]))
with open(os.environ["LOG"], "a") as log:
    log.write(json.dumps(args) + "\\n")
path = state["path"]
if args[:2] == ["worktree", "list"]:
    data = {"worktrees": [{"open_workspace_id": "fixture", "path": path}]}
elif args[:2] == ["workspace", "get"]:
    data = {"workspace": {"workspace_id": "fixture", "worktree": {"checkout_path": state.get("workspace_path", path)}}}
elif args[:2] == ["agent", "list"]:
    data = {"agents": [{"workspace_id": "fixture", "agent_status": state.get("agent", "done")}]}
elif args[:2] == ["worktree", "remove"]:
    if state.get("refuse"):
        print("fatal: worktree is locked", file=sys.stderr)
        sys.exit(1)
    sys.exit(subprocess.call(["git", "-C", state["repo"], "worktree", "remove", path] + (["--force"] if "--force" in args else [])))
else:
    sys.exit(90)
print(json.dumps({"result": data}))
''')
(fake / "herdr").chmod(0o755)
os.environ["PATH"] = str(fake) + os.pathsep + os.environ["PATH"]
# A sibling on PATH must never be used, even if a foreign shell supplies one.
(fake / "workbench-worktree-teardown").write_text("#!/bin/sh\nexit 99\n")
(fake / "workbench-worktree-teardown").chmod(0o755)


def fixture(name, *, hook=good, agent="done", main=False, sub=False, dirty=None,
            mismatch=False, foreign=False, refuse=False, explicit=True):
    case = root / name
    case.mkdir()
    repo = case / "repo"
    repo.mkdir()
    git(repo, "init", "-b", "main")
    git(repo, "config", "user.email", "fixture@example.invalid")
    git(repo, "config", "user.name", "Fixture")
    (repo / "tracked").write_text("original\n")
    git(repo, "add", ".")
    git(repo, "commit", "-m", "fixture")
    if sub:
        source = case / "sub-source"
        source.mkdir()
        git(source, "init", "-b", "main")
        git(source, "config", "user.email", "fixture@example.invalid")
        git(source, "config", "user.name", "Fixture")
        (source / "tracked").write_text("submodule\n")
        git(source, "add", ".")
        git(source, "commit", "-m", "submodule fixture")
        git(repo, "-c", "protocol.file.allow=always", "submodule", "add", str(source), "sub")
        git(repo, "commit", "-am", "submodule")
    path = repo if main else case / "linked tree"
    if not main:
        git(repo, "worktree", "add", "-b", "worker", str(path))
    if sub:
        git(path, "-c", "protocol.file.allow=always", "submodule", "update", "--init", "--recursive")
    if dirty == "tracked":
        (path / "tracked").write_text("keep tracked edits\n")
    if dirty == "untracked":
        (path / "untracked").write_text("keep untracked file\n")
    if dirty in ("serena", "mixed-serena"):
        (path / ".serena" / "cache").mkdir(parents=True)
        (path / ".serena" / "cache" / "runtime").write_text("keep runtime file\n")
        if dirty == "mixed-serena":
            (path / "untracked").write_text("keep unrelated file\n")
    if dirty == "sub":
        (path / "sub" / "untracked").write_text("keep nested file\n")
        git(path, "config", "submodule.sub.ignore", "all")
    state = case / "state.json"
    state.write_text(json.dumps({"repo": str(repo), "path": str(path), "agent": agent,
                                 "workspace_path": str(repo if mismatch else path), "refuse": refuse}))
    log = case / "calls.jsonl"
    os.environ.update(STATE=str(state), LOG=str(log), AGENTIC_WORKTREE_TEARDOWN="/nonexistent/inherited-teardown")
    cwd = root if foreign else repo
    if foreign:
        # Invoke from another repository to test independent membership proof.
        cwd = case / "other"
        cwd.mkdir()
        git(cwd, "init", "-b", "main")
    os.environ['XDG_STATE_HOME'] = str(case / 'service-state')
    lease_dir = case / 'service-state/workbench/services' / hashlib.sha256(os.fsencode(repo.resolve())).hexdigest()
    lease_dir.mkdir(parents=True)
    lease_path = lease_dir / 'database.json'
    lease_path.write_text(json.dumps({'service': 'database', 'attached': [str(path.resolve())], 'owner': 'fixture'}))
    args = [hook, "--workspace", "fixture"]
    if explicit:
        args += ["--worktree", str(path)]
    result = subprocess.run(args, cwd=cwd, capture_output=True, text=True)
    assert not result.stderr, result.stderr
    data = json.loads(result.stdout)
    calls = [json.loads(line) for line in log.read_text().splitlines()]
    assert calls[:2] == [["workspace", "get", "fixture"], ["worktree", "list", "--cwd", str(repo)]], calls
    if main or dirty or mismatch:
        assert data["teardown"]["status"] == "not-run", data
        assert not any(call[:2] == ["agent", "list"] for call in calls), calls
    elif agent != "done":
        assert data["teardown"]["status"] == "not-run", data
        assert [call for call in calls if call[:2] == ["agent", "list"]] == [["agent", "list"]], calls
    removals = [call for call in calls if call[:2] == ["worktree", "remove"]]
    success = hook == good and agent == "done" and not (main or dirty or mismatch or refuse)
    assert data["status"] == ("removed" if success else "refused"), data
    assert ("workbench-serena-ignore" in data["reason"]) == (dirty == "serena"), data
    if dirty in ("serena", "mixed-serena"):
        assert (path / ".serena" / "cache" / "runtime").read_text() == "keep runtime file\n"
    assert result.returncode == (0 if success else 1), data
    expected = [["worktree", "remove", "--workspace", "fixture"]] if success or refuse else []
    if success and sub:
        expected.append(expected[0] + ["--force"])
    assert removals == expected, (name, calls, data)
    if success:
        assert json.loads(lease_path.read_text())['attached'] == []
        assert not path.exists()
        assert git(repo, "branch", "--list", "worker") == "worker"
        assert data["teardown"]["verified"] == ["verified: resources absent"]
        assert data["teardown"]["stdout"].splitlines() == [
            "optional[optional-cleanup]: optional cleanup failed",
            "optional[optional-skipped]: skipped: optional resources unavailable",
            "optional[optional-skipped]: verified: optional proof is not required proof",
            "optional[optional-skipped]: ",
            "optional[optional-skipped]: SKIPPED: no trailing newline",
            "verified: resources absent",
        ], data
        assert data["teardown"]["status"] == "passed", data
    else:
        assert path.is_dir()
        if dirty == "tracked":
            assert (path / "tracked").read_text() == "keep tracked edits\n"
        if dirty == "untracked":
            assert (path / "untracked").read_text() == "keep untracked file\n"
        if dirty == "sub":
            assert (path / "sub" / "untracked").read_text() == "keep nested file\n"
    if hook in (bad, skipped) and not dirty:
        assert data["teardown"]["status"] == "failed"
        assert data["teardown"]["stdout"]
        assert data["teardown"]["stderr"]
    print(json.dumps({"case": name, "record": data, "remove_calls": removals}), flush=True)


try:
    fixture("clean-verified", explicit=False)
    fixture("teardown-exit", hook=bad)
    fixture("teardown-skipped", hook=skipped)
    fixture("dirty-tracked", dirty="tracked")
    fixture("untracked", dirty="untracked")
    fixture("serena-only", dirty="serena")
    fixture("mixed-serena", dirty="mixed-serena")
    fixture("agent-working", agent="working")
    fixture("agent-blocked", agent="blocked")
    fixture("main-checkout", main=True)
    fixture("clean-submodule", sub=True)
    fixture("dirty-submodule", sub=True, dirty="sub")
    fixture("workspace-mismatch", mismatch=True)
    # With no sibling names in PATH, both target-selection modes still work
    # from an unrelated repository and use this consumer's baked teardown.
    (fake / "workbench-worktree-teardown").unlink()
    assert shutil.which("workbench-worktree-teardown") is None
    fixture("foreign-repository", foreign=True)
    fixture("foreign-repository-workspace", foreign=True, explicit=False)
    fixture("foreign-repository-dirty", foreign=True, dirty="tracked")
    fixture("foreign-repository-mismatch", foreign=True, mismatch=True)
    fixture("unrelated-herdr-refusal", refuse=True)
finally:
    shutil.rmtree(root)
