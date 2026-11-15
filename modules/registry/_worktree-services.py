"""Shared repository services. No automatic stop, including on failed starts."""
import argparse
import contextlib
import datetime
import fcntl
import getpass
import hashlib
import json
import os
import re
import shlex
from pathlib import Path
import socket
import subprocess
import tempfile
import time


def run(*args, cwd=None):
    return subprocess.run(args, cwd=cwd, text=True, capture_output=True, timeout=30)


def identity():
    return os.environ.get("COTAL_NAME") or "user:" + getpass.getuser()


def main_checkout(worktree):
    result = run("git", "-C", str(worktree), "worktree", "list", "--porcelain", "-z")
    result.check_returncode()
    return Path(result.stdout.split("\0")[0][9:]).resolve()


def directory(main):
    state = Path(os.environ.get("XDG_STATE_HOME", str(Path.home() / ".local/state")))
    return state / "workbench/services" / hashlib.sha256(os.fsencode(main)).hexdigest()


@contextlib.contextmanager
def locked(main):
    folder = directory(main)
    folder.mkdir(parents=True, exist_ok=True)
    with (folder / ".lock").open("a") as lock:
        fcntl.flock(lock, fcntl.LOCK_EX)
        yield folder


def atomic(path, value):
    fd, name = tempfile.mkstemp(dir=path.parent, prefix=".lease-")
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(value, stream)
            stream.write("\n")
        os.replace(name, path)
    finally:
        if os.path.exists(name):
            os.unlink(name)


def probe(spec, main):
    try:
        if "tcp" in spec:
            host, port = spec["tcp"].rsplit(":", 1)
            with socket.create_connection((host.strip("[]"), int(port)), timeout=1):
                return True
        return subprocess.run(["bash", "-c", spec["run"]], cwd=main,
                              stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                              timeout=5).returncode == 0
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return False


class HerdrFailure(RuntimeError):
    def missing(self, resource):
        # Only explicit resource absence permits forgetting ownership. Transport,
        # authentication and other failures must retain the lease.
        return bool(re.search(r"\b" + resource + r"\b[^\n]*(?:not found|does not exist)|"
                              r"(?:not found|unknown)\s+" + resource + r"\b", str(self), re.I))


def herdr(*args):
    result = run("herdr", *args)
    if result.returncode:
        raise HerdrFailure((result.stderr or result.stdout)[-2048:] or "Herdr command failed")
    return json.loads(result.stdout)["result"]


def pane_exists(lease):
    if not lease:
        return None
    try:
        herdr("pane", "get", lease["pane"])
        return True
    except HerdrFailure as error:
        return False if error.missing("pane") else None
    except (OSError, ValueError, KeyError, TypeError, subprocess.SubprocessError):
        return None


def ensure(name, spec, worktree, main):
    result = {"attach": False, "owner": "external"}
    command = spec["start"] or "devenv up " + shlex.quote(spec["process"])
    lease = None
    def blocked(code, detail, attempted=False):
        status_command = shlex.join(["workbench-services", "--worktree", str(main), "status", name])
        remediation = (f"Service {name}; start command: {command}. Open main checkout {main} "
                       f"in Herdr, inspect the probe and retry setup. Inspect with `{status_command}`.")
        if lease:
            stop_command = shlex.join(["workbench-services", "--worktree", str(main), "stop", name])
            owner_option = " --as-owner " + shlex.quote(lease["owner"])
            detach_command = shlex.join(["workbench-services", "--worktree", str(worktree), "detach"])
            remediation = (f"Service {name}; start command: {lease['command']}. Lease {path}; "
                           f"owner {lease['owner']}; tab {lease['tab']}; pane {lease['pane']}. "
                           f"Inspect with `{status_command}`. Verify stale attachments before "
                           f"detaching with `{detach_command}` (repeat --worktree for each stale checkout). "
                           f"Once no worktrees are attached, run `{stop_command}` as the owner "
                           f"or explicitly `{stop_command}{owner_option}`, then retry setup.")
        return dict(result, blocker={"kind": "environment", "code": code,
            "step": "services[" + name + "]", "service": name, "probe": spec["probe"],
            "startAttempted": attempted, "detail": detail[-2048:],
            "remediation": remediation})
    with locked(main) as folder:
        path = folder / (name + ".json")
        lease = json.loads(path.read_text()) if path.exists() else None
        if lease:
            result.update(owner=lease["owner"], lease=str(path))
        if probe(spec["probe"], main):
            result["attach"] = True
            if lease:
                lease["attached"] = sorted(set(lease["attached"] + [str(worktree)]))
                atomic(path, lease)
                result.update(owner=lease["owner"], lease=str(path))
            return result
        if not spec["autostart"]:
            return blocked("service-unavailable", "Probe failed; autostart is disabled.")
        # An existing lease must not be overwritten: its tab may still be starting.
        if lease:
            result.update(owner=lease["owner"], lease=str(path))
            return blocked("service-unavailable", "Existing lease has a failed probe; inspect its tab before stopping/retrying.")
        try:
            matches = [w for w in herdr("workspace", "list")["workspaces"]
                       if w.get("worktree") and Path(w["worktree"]["checkout_path"]).resolve() == main]
            if not matches:
                return blocked("service-workspace-missing", "No Herdr workspace for " + str(main))
            workspace = matches[0]["workspace_id"]
            tab = herdr("tab", "create", "--workspace", workspace, "--cwd", str(main), "--label", "services:" + name)
            # Response fields are checked against the installed Herdr contract.
            pane = tab["root_pane"]["pane_id"]
            tab_id = tab["tab"]["tab_id"]
            lease = {"service": name, "owner": identity(), "startedFor": str(worktree),
                     "workspace": workspace, "tab": tab_id, "pane": pane, "command": command,
                     "startedAt": datetime.datetime.now(datetime.timezone.utc).isoformat(),
                     "attached": [str(worktree)]}
            atomic(path, lease)
            result.update(owner=lease["owner"], lease=str(path))
            herdr("pane", "run", pane, command)
            deadline = time.monotonic() + spec["startTimeout"]
            while True:
                if probe(spec["probe"], main):
                    return result
                if time.monotonic() >= deadline:
                    break
                time.sleep(min(1, max(0, deadline - time.monotonic())))
            detail = "Service did not become ready before startTimeout."
        except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
            detail = str(error)
        if lease:
            lease["state"] = "start-failed"
            atomic(path, lease)
        return blocked("service-unavailable", detail, True)


def detach(worktree, main):
    with locked(main) as folder:
        for path in folder.glob("*.json"):
            lease = json.loads(path.read_text())
            if str(worktree) in lease["attached"]:
                lease["attached"].remove(str(worktree))
                atomic(path, lease)


def cli():
    parser = argparse.ArgumentParser()
    parser.add_argument("--worktree", default=os.getcwd())
    parser.add_argument("--as-owner")
    parser.add_argument("action", choices=["status", "stop", "ensure", "detach"])
    parser.add_argument("name", nargs="?")
    args = parser.parse_args()
    worktree = Path(args.worktree).resolve()
    main = main_checkout(worktree)
    specs = json.loads(Path(os.environ["WORKBENCH_SERVICES_CONFIG"]).read_text())
    if args.name is not None and not re.fullmatch(r"[A-Za-z0-9_-]+", args.name):
        parser.error("service name must be an alphanumeric token with hyphens or underscores")
    if args.action in ("ensure", "stop") and not args.name:
        parser.error("service name is required")
    if args.action == "ensure":
        try:
            value = ensure(args.name, specs[args.name], worktree, main)
        except (OSError, ValueError, KeyError, TypeError) as error:
            value = {"attach": False, "owner": "external", "blocker": {
                "kind": "environment", "code": "service-unavailable", "service": args.name,
                "step": "services[" + args.name + "]", "probe": specs[args.name]["probe"],
                "startAttempted": False, "detail": str(error)[-2048:],
                "remediation": "Inspect service state/lease permissions and contents, then retry setup."}}
        print(json.dumps(value))
        return 0
    if args.action == "detach":
        detach(worktree, main)
        return 0
    with locked(main) as folder:
        if args.action == "status":
            names = sorted(set(specs) | {p.stem for p in folder.glob("*.json")})
            values = {}
            for name in names:
                if args.name and name != args.name:
                    continue
                path = folder / (name + ".json")
                lease = json.loads(path.read_text()) if path.exists() else None
                values[name] = {"lease": lease, "paneExists": pane_exists(lease),
                                "up": probe(specs[name]["probe"], main) if name in specs else None}
            print(json.dumps(values))
            return 0
        path = folder / (str(args.name) + ".json")
        if not path.exists():
            parser.exit(1, "Refused: external service (no workbench lease).\n")
        lease = json.loads(path.read_text())
        if lease["attached"]:
            parser.exit(1, "Refused: worktrees are still attached.\n")
        if lease["owner"] == "external" or (args.as_owner or identity()) != lease["owner"]:
            parser.exit(1, "Refused: caller does not match lease owner; use --as-owner explicitly.\n")
        missing_tab = False
        try:
            herdr("tab", "close", lease["tab"])
        except HerdrFailure as error:
            if not error.missing("tab"):
                raise
            missing_tab = True
        path.unlink()
        if missing_tab:
            print("lease removed; recorded tab no longer exists")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(cli())
    except (OSError, ValueError, KeyError, TypeError, RuntimeError, subprocess.SubprocessError) as error:
        import sys
        print("Service operation refused: " + str(error)[-2048:], file=sys.stderr)
        raise SystemExit(1)
