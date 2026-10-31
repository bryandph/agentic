"""Fail-closed coordinator removal barrier. External commands deliberately use PATH."""

import json
import os
import subprocess
import sys


class Refusal(Exception):
    pass


record = {
    "status": "failed",
    "reason": "",
    "workspace": None,
    "worktree": None,
    "teardown": {"status": "not-run", "verified": []},
    "herdr": {"attempts": []},
}


def run(*args):
    return subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)


def decode(value):
    return value.decode("utf-8", errors="replace")


def checked(*args):
    result = run(*args)
    if result.returncode:
        raise Refusal(f"{args[0]} {args[1]} failed: {decode(result.stderr).strip()}")
    return result.stdout


def herdr(*args):
    data = json.loads(checked("herdr", *args))
    return data["result"]


def canonical(path):
    return os.path.realpath(path)


def git(path, *args):
    return checked("git", "-C", path, "-c", "submodule.recurse=false", *args)


def clean(path):
    # Explicit flags override user settings that hide untracked/dirty submodules.
    status = git(path, "status", "--porcelain=v1", "-z", "--untracked-files=all", "--ignore-submodules=none")
    if status:
        entries = status.split(b"\0")
        paths = []
        while entries and entries[0]:
            entry = entries.pop(0)
            paths.append(decode(entry[3:]))
            if entry[:1] in (b"R", b"C") or entry[1:2] in (b"R", b"C"):
                paths.append(decode(entries.pop(0)))
        raise Refusal("dirty or untracked paths: " + json.dumps(paths, ensure_ascii=True))
    # --quiet suppresses foreach headings, not the nested command's stdout.
    nested = git(path, "submodule", "foreach", "--quiet", "--recursive",
                 "git status --porcelain=v1 --untracked-files=all --ignore-submodules=none")
    if nested:
        raise Refusal("dirty submodule paths: " + json.dumps([line[3:] for line in decode(nested).splitlines()]))


def agents_stopped(workspace):
    agents = herdr("agent", "list")["agents"]
    for agent in agents:
        if agent["workspace_id"] == workspace and agent["agent_status"] in ("working", "blocked"):
            raise Refusal("workspace agent is " + agent["agent_status"])


def remove():
    args = sys.argv[1:]
    options = {}
    while args:
        key = args.pop(0)
        if key not in ("--workspace", "--worktree") or key in options or not args:
            raise Refusal("usage: workbench-worktree-remove --workspace <id> [--worktree <path>]")
        options[key] = args.pop(0)
    workspace = options.get("--workspace")
    record["workspace"] = workspace
    record["worktree"] = options.get("--worktree")
    if not workspace:
        raise Refusal("--workspace is required")
    repo = decode(git(os.getcwd(), "rev-parse", "--show-toplevel")).strip()
    common = canonical(decode(git(repo, "rev-parse", "--path-format=absolute", "--git-common-dir")).strip())
    listing = herdr("worktree", "list", "--cwd", repo)["worktrees"]
    info = herdr("workspace", "get", workspace)["workspace"]
    if info["workspace_id"] != workspace:
        raise Refusal("workspace identity mismatch")
    workspace_path = canonical(info["worktree"]["checkout_path"])
    matches = [item for item in listing if item.get("open_workspace_id") == workspace]
    if len(matches) != 1 or canonical(matches[0]["path"]) != workspace_path:
        raise Refusal("Herdr worktree list and workspace checkout disagree")
    path = canonical(options.get("--worktree", workspace_path))
    record["worktree"] = path
    if path != workspace_path:
        raise Refusal("--worktree and workspace checkout disagree")
    # Independently verify Git membership; do not trust Herdr's linked flag.
    trees = git(repo, "worktree", "list", "--porcelain", "-z").split(b"\0")
    paths = [canonical(os.fsdecode(item[9:])) for item in trees if item.startswith(b"worktree ")]
    if not paths or path not in paths:
        raise Refusal("path is not a worktree of this repository")
    target_common = canonical(decode(git(path, "rev-parse", "--path-format=absolute", "--git-common-dir")).strip())
    target_git = canonical(decode(git(path, "rev-parse", "--absolute-git-dir")).strip())
    if target_common != common:
        raise Refusal("path belongs to another repository")
    if path == paths[0] or target_git == common:
        raise Refusal("main checkout cannot be removed")
    clean(path)
    agents_stopped(workspace)
    result = run("workbench-worktree-teardown", "--worktree", path)
    output = decode(result.stdout)
    record["teardown"] = {
        "status": "failed" if result.returncode else "passed",
        "exit_code": result.returncode,
        "stdout": output,
        "stderr": decode(result.stderr),
        "verified": [line for line in output.splitlines() if line.startswith("verified:")],
    }
    # The repository runner validates each hook, including absent proof. Also
    # reject skipped output defensively even if a substituted runner exits zero.
    if result.returncode or "skipped" in output.lower():
        record["teardown"]["status"] = "failed"
        raise Refusal("teardown did not verify cleanup")
    # Hooks may have changed the checkout; the evidence must still hold now.
    clean(path)
    agents_stopped(workspace)
    for force in (False, True):
        command = ["herdr", "worktree", "remove", "--workspace", workspace]
        if force:
            command.append("--force")
        result = run(*command)
        stdout, stderr = decode(result.stdout), decode(result.stderr)
        record["herdr"]["attempts"].append({"force": force, "exit_code": result.returncode, "stdout": stdout, "stderr": stderr})
        if not result.returncode:
            record["status"] = "removed"
            record["reason"] = "verified teardown and safe checkout removal"
            return
        # Git's specific initialized-submodule refusal, not generic mention of
        # submodules (which could conceal permission, lock or dirty-tree errors).
        if force or "containing submodules cannot be moved or removed" not in stdout + stderr:
            raise Refusal("Herdr refused removal; see herdr.attempts")
        clean(path)
        agents_stopped(workspace)


try:
    remove()
except Refusal as error:
    record["status"] = "refused"
    record["reason"] = str(error)
except (OSError, ValueError, KeyError, TypeError, IndexError) as error:
    record["reason"] = "cannot establish safe removal: " + str(error)
print(json.dumps(record, ensure_ascii=True))
sys.exit(0 if record["status"] == "removed" else 1)
