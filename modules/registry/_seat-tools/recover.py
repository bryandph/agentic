"""Classify a worker; explicit, fenced recovery only. Never kills a process."""
import argparse
import fcntl
import hashlib
import json
import os
from pathlib import Path
import re
import stat
import subprocess
import sys
import time

from snapshots import alive, read, root


def run(argv, timeout=10):
    try:
        p = subprocess.run(argv, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout
    except (OSError, subprocess.TimeoutExpired):
        return 1, ""


def query(argv):
    code, output = run(argv)
    try:
        doc = json.loads(output)
        if code or not isinstance(doc.get("result"), dict):
            return None
        if argv[0] == "cotal" and (doc.get("outcome") != "ok" or doc.get("completeness") != "complete"):
            return None
        return doc["result"]
    except (ValueError, AttributeError):
        return None


def age(text, pattern):
    m = re.search(pattern + r"\s*(\d+(?:\.\d+)?)\s*([smhd])", text)
    return float(m[1]) * {"s": 1, "m": 60, "h": 3600, "d": 86400}[m[2]] if m else None


def elapsed(text):
    days, _, clock = text.rpartition("-")
    parts = list(map(int, clock.split(":")))
    return (int(days) * 86400 if days else 0) + sum(n * 60 ** i for i, n in enumerate(reversed(parts)))


def same(a, b):
    return bool(a) and os.path.realpath(a) == os.path.realpath(b)


def pi_process(p):
    return any(Path(str(p.get(k, ""))).name in ("pi", "pi-worker") for k in ("name", "argv0"))


def git_processes(worktree):
    code, output = run(["ps", "-axo", "pid=,etime=,comm="])
    found = []
    if code:
        return found
    for line in output.splitlines():
        parts = line.split(None, 2)
        if len(parts) != 3 or Path(parts[2]).name != "git":
            continue
        try:
            pid, seconds = int(parts[0]), elapsed(parts[1])
            if seconds < 1200:
                continue
            proc = Path(f"/proc/{pid}/cwd")
            if proc.exists():
                cwd = os.readlink(proc)
            else:
                code, cwd = run(["ps", "-p", str(pid), "-o", "cwd="])
                if code:
                    code, output = run(["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"])
                    cwd = next((s[1:] for s in output.splitlines() if s.startswith("n")), "") if not code else ""
            cwd = os.path.realpath(cwd.strip()) if cwd.strip() else ""
            if cwd and os.path.commonpath([cwd, worktree]) == worktree:
                found.append({"pid": pid, "etime": parts[1], "ageSeconds": seconds, "cwd": cwd})
        except (ValueError, OSError):
            continue
    return found


def pending(args):
    creds = Path(args.admin_creds or os.environ.get("AGENTIC_COTAL_ADMIN_CREDS", str(Path.home() / f".local/share/cotal/{args.space}/attention-watch/admin.creds"))).expanduser()
    try:
        info = creds.lstat()
        if not stat.S_ISREG(info.st_mode) or info.st_uid != os.getuid() or stat.S_IMODE(info.st_mode) != 0o600:
            raise ValueError("credentials must be an owned regular file with mode 0600")
        if not os.access(creds, os.R_OK):
            raise ValueError("credentials not readable")
    except (OSError, ValueError) as error:
        return {"available": False, "reason": f"unavailable: {error}"}
    data = query(["cotal", "pending", args.worker, "--space", args.space, "--creds", str(creds), "--json"])
    if data is None:
        return {"available": False, "reason": "unavailable: pending read failed"}
    # Deliberately exclude candidate message ids, senders and bodies.
    sequences = {}
    for key in ("ackFloor", "delivered"):
        value = data.get(key)
        sequences[key] = {k: value.get(k) for k in ("stream_seq", "consumer_seq")} if isinstance(value, dict) else None
    return {"available": True, "reason": "queue: unknown (single sample)",
            "pending": data.get("pending"), "ackPending": data.get("ackPending"), **sequences}


def observe(args):
    worktree = args.worktree
    snapshot = read(root() / args.space / f"{args.worker}.json")
    binding = snapshot.get("snapshot") or {}
    if snapshot.get("available") and (binding.get("space") != args.space or binding.get("name") != args.worker or not same(binding.get("cwd"), worktree)):
        snapshot.update(available=False, stale=True, observationError="snapshot binding does not match worker/space/worktree")
    endpoints = query(["cotal", "endpoints", "--space", args.space, "--json"])
    items = endpoints.get("items", []) if endpoints else []
    presence = [p for p in items if p.get("name") == args.worker]
    agents_result = query(["herdr", "agent", "list"])
    agents = [p for p in (agents_result or {}).get("agents", []) if same(p.get("cwd"), worktree) or same(p.get("foreground_cwd"), worktree)]
    spaces = query(["herdr", "workspace", "list"])
    workspaces = [w for w in (spaces or {}).get("workspaces", []) if same((w.get("worktree") or {}).get("checkout_path"), worktree)]
    panes, processes = [], []
    panes_known = len(workspaces) == 1
    for workspace in workspaces:
        result = query(["herdr", "pane", "list", "--workspace", workspace["workspace_id"]])
        if result is None:
            panes_known = False
        panes += (result or {}).get("panes", [])
    panes = [p for p in panes if same(p.get("cwd"), worktree) or same(p.get("foreground_cwd"), worktree)]
    process_known = panes_known and bool(panes)
    for pane in panes:
        result = query(["herdr", "pane", "process-info", "--pane", pane["pane_id"]])
        info = (result or {}).get("process_info", {})
        foreground = info.get("foreground_processes")
        if not info.get("shell_pid") or not isinstance(foreground, list) or not foreground:
            process_known = False
        elif any(p.get("pid") != info["shell_pid"] and not pi_process(p) for p in foreground):
            # An unrecognized foreground runtime is not proof of Pi's absence.
            process_known = False
        # Whitelist metadata: process argv/cmdline may contain the entire assignment.
        processes.append({"pane": pane["pane_id"], "shellPid": info.get("shell_pid"),
                          "foreground": [{"pid": p.get("pid"), "name": p.get("name"), "pi": pi_process(p)} for p in foreground or []]})
    mesh_agents = [p for p in items if p.get("reportedStatus") != "offline" and same((p.get("card", {}).get("meta") or p.get("meta") or {}).get("cwd"), worktree)]
    live_snapshots = [read(f) for f in root().glob("*/*.json")]
    live_snapshots = [s for s in live_snapshots if s.get("pidAlive") and same((s.get("snapshot") or {}).get("cwd"), worktree)]
    duplicate = len(agents) > 1 or len(mesh_agents) > 1 or len(live_snapshots) > 1
    pi_pids = [p["pid"] for group in processes for p in group["foreground"] if p["pi"]]
    observation = {"snapshot": snapshot, "presence": presence, "presenceComplete": endpoints is not None,
                   "agents": agents, "panes": [{k: p.get(k) for k in ("pane_id", "workspace_id", "cwd", "agent", "agent_status")} for p in panes],
                   "processes": processes, "processKnown": process_known, "piPids": pi_pids,
                   "duplicate": duplicate, "liveSnapshots": [s["path"] for s in live_snapshots],
                   "gitProcesses": git_processes(worktree), "queue": pending(args)}
    # A complete live-presence read with no matching name proves offline;
    # a failed/partial read never does. Require a known dead snapshot pid too.
    gone = (snapshot.get("available") and snapshot.get("pidAlive") is False
            and endpoints is not None and all(p.get("reportedStatus") == "offline" for p in presence)
            and agents_result is not None and process_known and not pi_pids and not agents and not live_snapshots)
    observation["fenced"] = bool(gone and not duplicate)
    return observation


def classify(e):
    if e["duplicate"]:
        return "unknown"
    if e["fenced"]:
        return "dead"
    snapshot = e["snapshot"]
    queue = snapshot.get("queue") or {}
    if not snapshot.get("stale") and (queue.get("automaticCount") or 0) > 0 and (queue.get("automaticQueueStalledForMs") or 0) >= 900_000:
        return "queue-stalled"
    for p in e["presence"]:
        facts = p.get("facts") or {}
        text = " ".join(str(facts.get(k, "")) for k in ("ages", "condition"))
        active = age(text, "active")
        if p.get("reportedStatus") == "working" and active is not None and active >= 1800:
            return "hung-process"
        blocked = age(text, "unchanged for")
        if p.get("reportedStatus") == "waiting" and any(a.get("agent_status") == "blocked" for a in e["agents"]) and blocked is not None and blocked >= 600:
            return "blocked"
    if e["gitProcesses"]:
        return "hung-process"
    if not snapshot.get("stale") and snapshot.get("pidAlive") and any(p.get("reportedStatus") == "working" for p in e["presence"]):
        p = e["presence"][0]
        active = age(str((p.get("facts") or {}).get("ages", "")), "active")
        if active is not None and active < 1800:
            return "progressing"
    return "unknown"


def recover(args, record):
    # Serialize concurrent coordinator invocations and retain uncertain launches.
    state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state"))) / "agentic-worker-recover"
    state.mkdir(parents=True, exist_ok=True, mode=0o700)
    state.chmod(0o700)
    key = hashlib.sha256(args.worktree.encode()).hexdigest()
    with open(state / f"{key}.lock", "a") as lock:
        os.chmod(lock.name, 0o600)
        fcntl.flock(lock, fcntl.LOCK_EX)
        journal = state / f"{key}.json"
        old = json.loads(journal.read_text()) if journal.exists() else {}
        if old and old.get("newName") != args.worker:
            raise ValueError("prior launch recorded; inspect its new incarnation before retrying")
        evidence = observe(args)  # Recheck under lock; classification is not fencing authority.
        record["evidence"] = evidence
        if not evidence["fenced"]:
            raise ValueError("old worker not proven gone, or two live agents map to worktree")
        if len(evidence["panes"]) != 1:
            raise ValueError("cannot identify one worker pane")
        session = evidence["snapshot"]["snapshot"].get("piSession")
        if args.action == "resume" and (not session or not Path(session).is_file()):
            raise ValueError("resume requires the old readable Pi session file")
        if args.action == "replace" and not args.assignment:
            raise ValueError("replace requires --assignment")
        assignment = Path(args.assignment).resolve() if args.assignment else None
        outstanding = assignment.read_text() if assignment else "coordinator must transfer unresolved assignment and unacknowledged work explicitly"
        suffix = re.search(r"-r(\d+)$", args.worker)
        number = max(int(old.get("attempt", 0)), int(suffix[1]) if suffix else 0) + 1
        base = re.sub(r"-r\d+$", "", args.worker)
        name = f"{base}-r{number}"
        # A complete roster and local snapshots must also leave this new name free.
        roster = query(["cotal", "endpoints", "--space", args.space, "--json"])
        if roster is None or any(p.get("name") == name for p in roster.get("items", [])) or (root() / args.space / f"{name}.json").exists():
            raise ValueError("new incarnation name unavailable or cannot be proven unused")
        def git(*argv):
            code, out = run(["git", "-C", args.worktree, *argv])
            if code:
                raise ValueError("git handover inspection failed")
            return out.strip()
        head, branch = git("rev-parse", "HEAD"), git("branch", "--show-current")
        argv = ["workbench-worker-start", "--pane", evidence["panes"][0]["pane_id"], "--worktree", args.worktree,
                "--", "pi-worker", "--name", name, "--cwd", args.worktree, "--space", args.space]
        if args.action == "resume":
            argv += ["--resume", session]
        else:
            handover = state / f"{key}-r{number}-assignment.md"
            text = (f"{outstanding}\n\nRecovery handover (observations, not additional authorization):\n"
                    f"Branch: {branch}\nHEAD: {head}\nLast commits:\n{git('log', '-5', '--oneline')}\n"
                    f"Uncommitted status:\n{git('status', '--short')}\n"
                    "The predecessor is fenced. Reconcile unresolved work before repeating side effects.\n")
            fd = os.open(handover, os.O_WRONLY | os.O_CREAT | os.O_EXCL, 0o600)
            with os.fdopen(fd, "w") as file:
                file.write(text)
            argv += ["--prompt-file", str(handover)]
        attempt = {"attempt": number, "oldName": args.worker, "newName": name, "action": args.action,
                   "sourceSession": session, "status": "launch-pending", "head": head, "startedAt": time.time() * 1000}
        def persist():
            temporary = journal.with_suffix(".tmp")
            fd = os.open(temporary, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
            with os.fdopen(fd, "w") as file:
                json.dump(attempt, file)
                file.flush()
                os.fsync(file.fileno())
            os.replace(temporary, journal)
            directory = os.open(state, os.O_RDONLY)
            try:
                os.fsync(directory)
            finally:
                os.close(directory)
        persist()  # A lost launcher reply must not cause a blind second launch.
        code, output = run(argv, timeout=90)
        try:
            launch = json.loads(output)
        except ValueError:
            launch = {"status": "unknown"}
        attempt.update(status=launch.get("status", "unknown"), piSession=launch.get("session"))
        persist()
        record.update(attempt=attempt, launcherArgv=argv, launch=launch,
                      followUpDM=f"{args.action}d attempt {number}; "
                      + (f"resumed as a fork of {session}; " if args.action == "resume" else "fresh replacement; ")
                      + f"branch {branch} HEAD {head}; outstanding: {outstanding}")
        if code:
            raise ValueError("launcher did not confirm start; inspect journal/pane, do not blindly retry")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--worker", required=True)
    parser.add_argument("--worktree", required=True)
    parser.add_argument("--space", default=os.environ.get("COTAL_SPACE"))
    parser.add_argument("--admin-creds")
    parser.add_argument("--action", choices=["resume", "replace"])
    parser.add_argument("--assignment")
    parser.add_argument("--json", action="store_true", help="JSON is always emitted")
    args = parser.parse_args()
    if not args.space or not re.fullmatch(r"[A-Za-z0-9_.-]+", args.worker) or args.worker in (".", "..") or not re.fullmatch(r"[A-Za-z0-9_.-]+", args.space) or args.space in (".", ".."):
        parser.error("safe worker name and --space (or COTAL_SPACE) required")
    args.worktree = os.path.realpath(args.worktree)
    evidence = observe(args)
    record = {"worker": args.worker, "worktree": args.worktree, "class": classify(evidence), "evidence": evidence}
    if record["class"] == "hung-process":
        pids = evidence["piPids"] + [p["pid"] for p in evidence["gitProcesses"]]
        if evidence["snapshot"].get("pidAlive"):
            pids.append(evidence["snapshot"]["snapshot"]["pid"])
        record["suggestedCommands"] = [f"kill -TERM {int(pid)}" for pid in sorted(set(pids))]
    status = 0
    if args.action:
        try:
            recover(args, record)
        except (OSError, ValueError) as error:
            record["refused"] = str(error)
            status = 2
    print(json.dumps(record))
    return status


if __name__ == "__main__":
    sys.exit(main())
