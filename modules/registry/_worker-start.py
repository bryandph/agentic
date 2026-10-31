"""One launch, bounded observation; readiness is not assignment acceptance."""

import argparse
import datetime
import json
import math
import os
import re
import subprocess
import sys
import time


ANSI = re.compile(r"\x1b(?:\][^\x07]*(?:\x07|\x1b\\)|\[[0-?]*[ -/]*[@-~]|[@-_])")


def tail(text):
    lines = []
    for line in ANSI.sub("", text).splitlines()[-40:]:
        line = re.sub(r"(.)\1{7,}", lambda match: f"{match[1]}…(×{len(match[0])})", line.rstrip())
        lines.append(line[:240])
    # UTF-8 byte cap is stricter than the character cap for Unicode terminals.
    return "\n".join(lines).encode("utf-8")[-4096:].decode("utf-8", errors="ignore")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pane", required=True)
    parser.add_argument("--worktree", required=True)
    parser.add_argument("--timeout", type=float, default=30, help="seconds (default: 30)")
    parser.add_argument("launcher", nargs=argparse.REMAINDER)
    args = parser.parse_args()
    argv = args.launcher
    if argv[:1] == ["--"]:
        argv = argv[1:]
    if not argv or not math.isfinite(args.timeout) or args.timeout <= 0:
        parser.error("a launcher and a finite positive timeout are required")
    worktree = os.path.abspath(args.worktree)
    info = {}
    evidence = ""
    diagnostics = []
    explanation = {}

    def run(command, timeout=5):
        try:
            result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
            return result.returncode, result.stdout, result.stderr
        except (OSError, subprocess.TimeoutExpired) as error:
            return 1, "", str(error)

    def herdr(*command, timeout=5):
        code, out, err = run(["herdr", *command], timeout)
        try:
            data = json.loads(out).get("result", {})
        except (ValueError, AttributeError):
            data = {}
        return code, data, out + err

    def finish(status, reason):
        # The last successful tail survives a vanished pane.
        record = dict(status=status, pane=args.pane, workspace=info.get("workspace_id"),
                      worktree=worktree, agent=info.get("agent"),
                      session=(info.get("agent_session") or {}).get("value"),
                      agentStatus=info.get("agent_status"), evidence=tail(evidence),
                      reason=reason, fallback_reason=explanation.get("fallback_reason"),
                      visible_blocker=explanation.get("visible_blocker"),
                      diagnostics=tail("\n".join(diagnostics)),
                      ts=datetime.datetime.now(datetime.timezone.utc).isoformat())
        print(json.dumps(record))
        return {"started": 0, "blocked": 10, "not-started": 11, "launch-failed": 20, "setup-failed": 30}[status]

    code, out, err = run(["workbench-worktree-setup", "--check", worktree], timeout=30)
    if code:
        diagnostics.append(out + err)
        return finish("setup-failed", "worktree setup check failed")
    for index, arg in enumerate(argv):
        if arg == "--prompt-file" or arg.startswith("--prompt-file="):
            path = arg.split("=", 1)[1] if "=" in arg else (argv[index + 1] if index + 1 < len(argv) else "")
            # Relative launcher paths are resolved in the target worktree.
            path = path if os.path.isabs(path) else os.path.join(worktree, path)
            try:
                with open(path, "rb"):
                    pass
            except OSError as error:
                diagnostics.append(str(error))
                return finish("launch-failed", "prompt file missing or unreadable")

    code, data, message = herdr("pane", "get", args.pane)
    if code:
        diagnostics.append(message)
        return finish("launch-failed", "pane unavailable before launch")
    info = data.get("pane", {})
    if info.get("agent"):
        return finish("launch-failed", "pane already contains an agent; launch refused")
    code, data, message = herdr("pane", "process-info", "--pane", args.pane)
    process = data.get("process_info", {})
    foreground = process.get("foreground_processes", [])
    shell = process.get("shell_pid")
    if code or not shell or not foreground or any(p.get("pid") != shell for p in foreground):
        diagnostics.append(message if code else "pane is not an available foreground shell")
        return finish("launch-failed", "cannot verify available shell; launch refused")
    if os.path.realpath(info.get("cwd", "")) != os.path.realpath(worktree):
        return finish("launch-failed", "pane cwd does not match worktree; launch refused")

    # A single-quoted Python trampoline is valid in both POSIX shells and Nu.
    # Hex JSON preserves every argv byte without shell interpolation, including
    # apostrophes, newlines, dollars and leading dashes. No exec: the pane's
    # interactive shell survives failures, retaining their terminal evidence.
    payload = json.dumps(argv).encode().hex()
    command = (f"{sys.executable} -c 'import json,shlex,subprocess; "
               f'argv=json.loads(bytes.fromhex("{payload}")); '
               'print("workbench-worker-start: launching:", shlex.join(argv), flush=True); '
               'raise SystemExit(subprocess.call(argv))\'')
    code, _, message = herdr("pane", "run", args.pane, command)
    if code:
        diagnostics.append(message)
        return finish("launch-failed", "Herdr rejected launch (not retried)")
    launched_at = time.monotonic()
    deadline = launched_at + args.timeout
    while True:
        code, data, message = herdr("pane", "get", args.pane)
        if code:
            diagnostics.append(message)
            return finish("launch-failed", "pane vanished or became unavailable")
        info = data.get("pane", {})
        code, _, output = herdr("pane", "read", args.pane, "--source", "recent-unwrapped", "--lines", "40", "--raw")
        if not code:
            evidence = tail(output)
        code, data, _ = herdr("agent", "get", args.pane)
        if not code:
            info.update(data.get("agent", {}))
        state = info.get("agent_status")
        if info.get("agent") and state in ("working", "blocked"):
            return finish("started" if state == "working" else "blocked", "Herdr observed " + state)
        # Process metadata, never terminal-text prompt heuristics. Allow
        # queued input time to leave the shell before recognizing its return.
        if time.monotonic() - launched_at > 0.5:
            code, data, _ = herdr("pane", "process-info", "--pane", args.pane)
            process = data.get("process_info", {})
            foreground = process.get("foreground_processes", [])
            shell = process.get("shell_pid")
            if not code and shell and foreground and all(p.get("pid") == shell for p in foreground):
                return finish("launch-failed", "launcher exited; foreground returned to shell")
        remaining = deadline - time.monotonic()
        if remaining <= 0:
            _, _, output = herdr("agent", "explain", args.pane, "--json")
            try:
                full = json.loads(output)
                # Keep lifecycle facts, not the repeated detector buffer previews.
                keys = ("state", "fallback_reason", "visible_blocker", "visible_idle",
                        "visible_working", "manifest_version", "matched_rule")
                explanation = {key: full[key] for key in keys if key in full}
                diagnostics.append(json.dumps(explanation, ensure_ascii=False, indent=2))
            except (ValueError, TypeError):
                explanation = {}
                diagnostics.append(output)
            status = "not-started" if info.get("agent") else "launch-failed"
            return finish(status, "timeout: Herdr did not observe working or blocked")
        # Short waits allow evidence collection even when a process/pane exits.
        # agent-not-found can return immediately, hence the bounded sleep.
        herdr("agent", "wait", args.pane, "--until", "working", "--until", "blocked",
              "--timeout", str(max(1, int(min(remaining, 0.25) * 1000))), timeout=min(remaining, 0.25) + 1)
        time.sleep(min(0.05, max(0, deadline - time.monotonic())))


if __name__ == "__main__":
    sys.exit(main())
